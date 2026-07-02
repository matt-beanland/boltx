# SPDX-FileCopyrightText: 2024 bolty contributors
# SPDX-License-Identifier: Apache-2.0

defmodule Bolty.Client do
  @moduledoc false

  @handshake_bytes_identifier <<0x60, 0x60, 0xB0, 0x17>>
  @summary ~w(success ignored failure)a

  import Bolty.BoltProtocol.ServerResponse

  alias Bolty.BoltProtocol.Versions
  alias Bolty.Utils.Converters
  alias Bolty.BoltProtocol.MessageDecoder

  alias Bolty.BoltProtocol.Message.{
    HelloMessage,
    LogonMessage,
    RunMessage,
    PullMessage,
    BeginMessage,
    CommitMessage,
    RollbackMessage,
    ResetMessage,
    GoodbyeMessage,
    DiscardMessage,
    LogoffMessage
  }

  defstruct [:sock, :bolt_version, policy: %Bolty.Policy{}]

  defmodule Config do
    @moduledoc false

    @default_timeout 15_000

    defstruct [
      :hostname,
      :port,
      :scheme,
      :username,
      :password,
      :connect_timeout,
      :socket_options,
      :versions,
      :ssl?,
      :tls_verify,
      :ssl_opts
    ]

    def new(opts) do
      {hostname, port} = get_hostname_and_port(opts)
      {username, password} = get_user_and_pass(opts)
      {scheme, ssl?, tls_verify, ssl_opts} = get_scheme_and_ssl_opts(opts)
      versions = get_versions(opts)

      %__MODULE__{
        hostname: hostname,
        port: port,
        scheme: scheme,
        username: username,
        password: password,
        connect_timeout: Keyword.get(opts, :connect_timeout, @default_timeout),
        socket_options:
          Keyword.merge([mode: :binary, packet: :raw, active: false], opts[:socket_options] || []),
        versions: versions,
        ssl?: ssl?,
        tls_verify: tls_verify,
        ssl_opts: ssl_opts
      }
    end

    # Maps the connection scheme to a TLS *intent*, not materialised ssl options:
    # the strict defaults (incl. SNI, which needs the hostname) are built at
    # connect time in Client.maybe_connect_to_ssl/2. Per Neo4j scheme semantics
    # (matching the official drivers):
    #
    #   * bolt / neo4j        -> no TLS
    #   * bolt+s / neo4j+s    -> full verification (verify_peer against system CAs)
    #   * bolt+ssc / neo4j+ssc -> self-signed / trust-all (encrypt only, no verify)
    #
    # User-supplied :ssl_opts are returned raw and merged *over* the strict
    # defaults at connect time, so an explicit `verify:`/`cacertfile:` always wins.
    defp get_scheme_and_ssl_opts(opts) do
      scheme = get_schema(opts)
      ssl_opts = Keyword.get(opts, :ssl_opts, [])

      {ssl?, tls_verify} =
        case scheme do
          "bolt" -> {false, :none}
          "neo4j" -> {false, :none}
          "bolt+s" -> {true, :verify}
          "neo4j+s" -> {true, :verify}
          "bolt+ssc" -> {true, :self_signed}
          "neo4j+ssc" -> {true, :self_signed}
          # Unknown scheme: secure by default.
          _ -> {true, :verify}
        end

      {scheme, ssl?, tls_verify, ssl_opts}
    end

    defp get_user_and_pass(opts) do
      basic_auth = Keyword.get(opts, :auth, [])

      username =
        System.get_env("BOLT_USER") || Keyword.get(basic_auth, :username, nil) ||
          raise(":username is missing")

      password = System.get_env("BOLT_PWD") || Keyword.get(basic_auth, :password)

      {username, password}
    end

    defp get_hostname_and_port(opts) do
      uri = Keyword.get(opts, :uri, nil)

      parsed_uri =
        uri
        |> to_string
        |> URI.parse()

      port_default = String.to_integer(System.get_env("BOLT_TCP_PORT") || "7687")

      hostname =
        parsed_uri.host || Keyword.get(opts, :hostname, nil) || System.get_env("BOLT_HOST") ||
          "localhost"

      port = parsed_uri.port || Keyword.get(opts, :port, port_default)
      {hostname, port}
    end

    defp get_schema(opts) do
      uri = Keyword.get(opts, :uri, nil)

      parsed_uri =
        uri
        |> to_string
        |> URI.parse()

      parsed_uri.scheme || Keyword.get(opts, :scheme, nil) || "bolt+s"
    end

    def get_versions(opts) do
      versions =
        case Keyword.get(opts, :versions) do
          nil ->
            case System.get_env("BOLT_VERSIONS") do
              nil ->
                Versions.latest_versions()

              env_versions ->
                require Logger

                Logger.warning(
                  "BOLT_VERSIONS env var is deprecated — set :versions in your connection config instead"
                )

                env_versions
                |> String.split(",")
                |> Enum.map(&Converters.to_float/1)
            end

          ops_versions ->
            ops_versions
        end

      ((versions |> Enum.into([])) ++ [0, 0, 0]) |> Enum.take(4) |> Enum.sort(&>=/2)
    end
  end

  def connect(%Config{} = config) do
    with {:ok, client} <- do_connect(config) do
      handshake(client, config)
    end
  end

  def connect(opts) when is_list(opts) do
    connect(Config.new(opts))
  end

  def do_connect(config) do
    client = %__MODULE__{sock: nil, bolt_version: nil}

    case maybe_connect_to_ssl(client, config) do
      {:ok, client} ->
        {:ok, client}

      other ->
        other
    end
  end

  defp maybe_connect_to_ssl(client, %{ssl?: false} = config) do
    %{
      hostname: hostname,
      port: port,
      socket_options: socket_options,
      connect_timeout: connect_timeout
    } = config

    case :gen_tcp.connect(String.to_charlist(hostname), port, socket_options, connect_timeout) do
      {:ok, sock} ->
        {:ok, %{client | sock: {:gen_tcp, sock}}}

      {:error, reason} ->
        {:error, wrap_connect_error(reason)}
    end
  end

  defp maybe_connect_to_ssl(client, %{ssl?: true} = config) do
    %{
      hostname: hostname,
      port: port,
      socket_options: socket_options,
      connect_timeout: connect_timeout,
      tls_verify: tls_verify,
      ssl_opts: ssl_opts
    } = config

    opts = build_tls_opts(tls_verify, hostname, ssl_opts, socket_options)

    case :ssl.connect(String.to_charlist(hostname), port, opts, connect_timeout) do
      {:ok, ssl_sock} ->
        {:ok, %{client | sock: {:ssl, ssl_sock}}}

      {:error, reason} ->
        {:error, wrap_connect_error(reason)}
    end
  end

  # Normalise a raw :gen_tcp/:ssl connect error into a %Bolty.Error{}. Reasons are
  # posix atoms (:econnrefused, :nxdomain, :timeout, …) or, for TLS, a
  # {:tls_alert, {alert, description}} tuple — keep the alert legible so a
  # verification failure is diagnosable. Anything else is preserved via inspect.
  defp wrap_connect_error(reason) when is_atom(reason) do
    Bolty.Error.wrap(__MODULE__, reason)
  end

  defp wrap_connect_error({:tls_alert, {alert, description}}) do
    Bolty.Error.wrap(__MODULE__, %{code: :tls_alert, message: "#{alert}: #{description}"})
  end

  defp wrap_connect_error(reason) do
    Bolty.Error.wrap(__MODULE__, %{code: :connect_error, message: inspect(reason)})
  end

  # Assembles the final :ssl.connect options. Layering (last wins): strict TLS
  # defaults < user :ssl_opts < transport socket options. User opts override
  # verification/CA config so an explicit `verify:`/`cacertfile:` always takes
  # effect; transport options (mode/packet/active) are structural and stay
  # authoritative. Public (within this @moduledoc false module) so the
  # precedence can be unit-tested without a live TLS server.
  def build_tls_opts(tls_verify, hostname, ssl_opts, socket_options) do
    tls_verify
    |> tls_default_opts(hostname)
    |> Keyword.merge(ssl_opts)
    |> put_default_cacerts()
    |> Keyword.merge(socket_options)
  end

  # Supply the OS trust store as the default CA source for verify_peer — but only
  # when the user hasn't provided their own. :cacerts and :cacertfile are
  # mutually exclusive in :ssl (if both are present :cacerts wins and :cacertfile
  # is ignored), so injecting a default :cacerts unconditionally would silently
  # override a user's `ssl_opts: [cacertfile: ...]`. Applied after the user merge
  # so their CA choice, and any `verify: :verify_none` override, take effect.
  defp put_default_cacerts(opts) do
    cond do
      opts[:verify] != :verify_peer -> opts
      Keyword.has_key?(opts, :cacertfile) -> opts
      Keyword.has_key?(opts, :cacerts) -> opts
      true -> Keyword.put(opts, :cacerts, :public_key.cacerts_get())
    end
  end

  # Strict, secure-by-default TLS options per scheme intent. Built here (not at
  # scheme-mapping time) because server_name_indication needs the resolved
  # hostname. `+s` gets full CA verification + hostname check; `+ssc` is the
  # documented self-signed / trust-all opt-out (encrypt only). Callers can still
  # override any of these via :ssl_opts, which are merged on top. The CA source
  # for :verify is added separately by put_default_cacerts/1.
  defp tls_default_opts(:verify, hostname) do
    [
      verify: :verify_peer,
      depth: 3,
      server_name_indication: String.to_charlist(hostname),
      customize_hostname_check: [
        match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
      ]
    ]
  end

  defp tls_default_opts(:self_signed, hostname) do
    [
      verify: :verify_none,
      server_name_indication: String.to_charlist(hostname)
    ]
  end

  defp handshake(client, config) do
    case do_handshake(client, config) do
      {:ok, client} ->
        {:ok, client}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_handshake(client, config) do
    data =
      @handshake_bytes_identifier <>
        (config.versions
         |> Enum.sort(&>=/2)
         |> Enum.reduce(<<>>, fn version, acc -> acc <> Versions.to_bytes(version) end))

    with :ok <- send_packet(client, data),
         encode_version <- recv_packets(client, config.connect_timeout),
         version <- decode_version(encode_version) do
      case version do
        +0.0 -> {:error, Bolty.Error.wrap(__MODULE__, :version_negotiation_error)}
        _ -> {:ok, %{client | bolt_version: version}}
      end
    else
      _ ->
        {:error, Bolty.Error.wrap(__MODULE__, :version_negotiation_error)}
    end
  end

  def prepare_generic_messages(_bolt_version, messages) do
    response = hd(messages)

    case response do
      {:success, response} ->
        {:ok, response}

      {:ignored, _} ->
        {:error, Bolty.Error.wrap(__MODULE__, :ignored)}

      {:failure, response} ->
        {:error,
         Bolty.Error.wrap(__MODULE__, %{
           code: response["neo4j_code"] || response["code"],
           message: response["description"] || response["message"]
         })}
    end
  end

  def send_hello(client, fields) do
    payload = HelloMessage.encode(client.bolt_version, [{:policy, client.policy} | fields])

    with :ok <- send_packet(client, payload) do
      recv_packets(client, &__MODULE__.prepare_generic_messages/2, :infinity)
    end
  end

  def send_logon(client, fields) do
    payload = LogonMessage.encode(client.bolt_version, fields)

    with :ok <- send_packet(client, payload) do
      recv_packets(client, &__MODULE__.prepare_generic_messages/2, :infinity)
    end
  end

  def send_run(client, query, parameters, extra_parameters) do
    payload =
      RunMessage.encode(client.bolt_version, query, parameters, extra_parameters, client.policy)

    with :ok <- send_packet(client, payload) do
      recv_packets(client, &RunMessage.prepare_messages/2, :infinity)
    end
  end

  def send_pull(client, extra_parameters) do
    payload = PullMessage.encode(client.bolt_version, extra_parameters)

    with :ok <- send_packet(client, payload) do
      recv_packets(client, &PullMessage.prepare_messages/2, :infinity)
    end
  end

  def run_statement(client, query, parameters, extra_parameters) do
    with {:ok, result_run} <- send_run(client, query, parameters, extra_parameters),
         {:ok, result_pull} <- send_pull(client, extra_parameters) do
      {:ok, statement_result(result_run: result_run, result_pull: result_pull, query: query)}
    end
  end

  def run_statement(client, %Bolty.Query{} = query, parameters) do
    %Bolty.Query{statement: statement, extra: extra_parameters} = query

    run_statement(client, statement, parameters, extra_parameters)
  end

  def run_statement(client, %Bolty.Queries{} = queries, parameters) do
    %Bolty.Queries{statement: statement, extra: extra_parameters} = queries

    cypher_seps = ~r/;(.){0,1}\n/

    statements =
      statement
      |> String.split(cypher_seps, trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.filter(&(String.length(&1) > 0))

    Enum.reduce_while(statements, {:ok, []}, fn statement, {:ok, acc} ->
      case Bolty.Client.run_statement(client, statement, parameters, extra_parameters) do
        {:ok, result} -> {:cont, {:ok, [result | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  def send_begin(client, extra_parameters) do
    payload = BeginMessage.encode(client.bolt_version, extra_parameters)

    with :ok <- send_packet(client, payload) do
      recv_packets(client, &__MODULE__.prepare_generic_messages/2, :infinity)
    end
  end

  def send_commit(client) do
    payload = CommitMessage.encode(client.bolt_version)

    with :ok <- send_packet(client, payload) do
      recv_packets(client, &__MODULE__.prepare_generic_messages/2, :infinity)
    end
  end

  def send_rollback(client) do
    payload = RollbackMessage.encode(client.bolt_version)

    with :ok <- send_packet(client, payload) do
      recv_packets(client, &__MODULE__.prepare_generic_messages/2, :infinity)
    end
  end

  def send_reset(client) do
    payload = ResetMessage.encode(client.bolt_version)

    with :ok <- send_packet(client, payload) do
      recv_packets(client, &__MODULE__.prepare_generic_messages/2, :infinity)
    end
  end

  def send_discard(client, extra_parameters) do
    payload = DiscardMessage.encode(client.bolt_version, extra_parameters)

    with :ok <- send_packet(client, payload) do
      recv_packets(client, &DiscardMessage.prepare_messages/2, :infinity)
    end
  end

  def send_goodbye(client) do
    payload = GoodbyeMessage.encode(client.bolt_version)

    with {:error, :closed} <- send_packet(client, payload) do
      try do
        disconnect(client)
        :ok
      rescue
        ArgumentError ->
          {:error,
           Bolty.Error.wrap(__MODULE__, %{
             code: :failed_port_close,
             message: "Error closing port with goodbye message"
           })}
      end
    end
  end

  def send_logoff(client) do
    payload = LogoffMessage.encode(client.bolt_version)

    with :ok <- send_packet(client, payload) do
      recv_packets(client, &__MODULE__.prepare_generic_messages/2, :infinity)
    end
  end

  def send_ping(client) do
    case run_statement(client, "RETURN true as success", %{}, %{}) do
      {:ok, statement_result(result_pull: pull_result(records: [[true]]))} ->
        {:ok, true}

      _ ->
        {:error, :db_ping_failed}
    end
  end

  defp decode_version(<<0, 0, minor::unsigned-integer, major::unsigned-integer>>)
       when is_integer(major) and is_integer(minor) do
    Float.round(major + minor / 10.0, 1)
  end

  def send_packet(client, payload) do
    send_data(client, payload)
  end

  def send_data(%{sock: {sock_mod, sock}}, data) do
    sock_mod.send(sock, data)
  end

  def recv_packets(client, timeout) do
    case recv_data(client, timeout) do
      {:ok, response} ->
        response

      {:error, :timeout} ->
        {:error, Bolty.Error.wrap(__MODULE__, :timeout)}

      {:error, _} = error ->
        error
    end
  end

  def recv_packets(client, prepare_messages, timeout) do
    recv_packets(client, prepare_messages, timeout, [])
  end

  defp recv_packets(client, prepare_messages, timeout, messages) do
    case get_next_message(client, timeout) do
      {:ok, {status, _} = message_summary} when status in @summary ->
        prepare_messages.(client.bolt_version, [message_summary | messages])

      {:ok, message_record} ->
        recv_packets(client, prepare_messages, timeout, [message_record | messages])

      {:error, _} = error ->
        error
    end
  end

  defp get_next_message(client, timeout) do
    with {:ok, message_binary} <- read_chunks(client, timeout, <<>>),
         {:ok, message} <- decode_message(message_binary) do
      {:ok, message}
    end
  end

  # A Bolt message is transmitted as one or more chunks, each prefixed with a
  # uint16 length, and terminated by a zero-length (0x0000) chunk. Accumulate the
  # chunk payloads until that end-marker, then return the concatenated message
  # body. This correctly reassembles a message the server splits across several
  # chunks — which the protocol permits for any message, not only those larger
  # than 65_535 bytes — rather than assuming one chunk per message.
  #
  # A 0x0000 read with nothing accumulated is a standalone NOOP / keep-alive
  # boundary, so it is skipped rather than decoded as an empty message.
  defp read_chunks(client, timeout, acc) do
    case get_chunk_size(client, timeout) do
      {:ok, 0} when acc == <<>> ->
        read_chunks(client, timeout, acc)

      {:ok, 0} ->
        {:ok, acc}

      {:ok, chunk_size} ->
        with {:ok, chunk} <- get_chunk(client, timeout, chunk_size) do
          read_chunks(client, timeout, <<acc::binary, chunk::binary>>)
        end

      {:error, _} = error ->
        error
    end
  end

  defp get_chunk_size(client, timeout) do
    case recv_data(client, timeout, 2) do
      {:ok, <<chunk_size::16>>} ->
        {:ok, chunk_size}

      {:error, reason} ->
        {:error, Bolty.Error.wrap(__MODULE__, reason)}
    end
  end

  defp get_chunk(client, timeout, chunk_size) do
    case recv_data(client, timeout, chunk_size) do
      {:ok, <<chunk::binary>>} ->
        {:ok, chunk}

      {:error, reason} ->
        {:error, Bolty.Error.wrap(__MODULE__, reason)}
    end
  end

  defp decode_message(message_binary) do
    message = MessageDecoder.decode(message_binary)
    {:ok, message}
  end

  def recv_data(%{sock: {sock_mod, sock}}, timeout, length \\ 0) do
    sock_mod.recv(sock, length, timeout)
  end

  def disconnect(client) do
    {sock_mod, sock} = client.sock
    sock_mod.close(sock)
    :ok
  end
end
