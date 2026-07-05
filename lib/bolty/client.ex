# SPDX-FileCopyrightText: 2024 bolty contributors
# SPDX-License-Identifier: Apache-2.0

defmodule Bolty.Client do
  @moduledoc false

  @handshake_bytes_identifier <<0x60, 0x60, 0xB0, 0x17>>
  @summary ~w(success ignored failure)a

  import Bolty.BoltProtocol.ServerResponse

  alias Bolty.BoltProtocol.Versions
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

  defstruct [:sock, :bolt_version, :recv_timeout, policy: %Bolty.Policy{}]

  defmodule Config do
    @moduledoc false

    @default_timeout 15_000
    @default_port 7687

    # Redact the password so a failed-connect crash report (DBConnection includes
    # state/opts) can't leak it to logs.
    @derive {Inspect, except: [:password]}
    defstruct [
      :hostname,
      :port,
      :scheme,
      :username,
      :password,
      :connect_timeout,
      :recv_timeout,
      :socket_options,
      :versions,
      :ssl?,
      :tls_verify,
      :ssl_opts
    ]

    @doc """
    Builds a `%Config{}` from connection options.

    Returns `{:ok, config}`, or `{:error, %Bolty.Error{}}` when a required field
    (currently `:username`) is missing, or when `:versions` contains no version
    bolty actually implements — either way the caller surfaces that cleanly
    rather than raising (or silently misbehaving) inside DBConnection's connect
    callback.
    """
    def new(opts) do
      {hostname, port} = get_hostname_and_port(opts)
      {username, password} = get_user_and_pass(opts)
      {scheme, ssl?, tls_verify, ssl_opts} = get_scheme_and_ssl_opts(opts)

      with :ok <- validate_username(username),
           {:ok, versions} <- get_versions(opts) do
        {:ok,
         %__MODULE__{
           hostname: hostname,
           port: port,
           scheme: scheme,
           username: username,
           password: password,
           connect_timeout: Keyword.get(opts, :connect_timeout, @default_timeout),
           recv_timeout: Keyword.get(opts, :recv_timeout, @default_timeout),
           socket_options:
             Keyword.merge(
               [mode: :binary, packet: :raw, active: false],
               opts[:socket_options] || []
             ),
           versions: versions,
           ssl?: ssl?,
           tls_verify: tls_verify,
           ssl_opts: ssl_opts
         }}
      end
    end

    defp validate_username(nil) do
      {:error,
       Bolty.Error.wrap(Bolty.Client, %{
         code: :missing_username,
         message: ":username is missing — set auth: [username: ...] in your connection config"
       })}
    end

    defp validate_username(_username), do: :ok

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
      {Keyword.get(basic_auth, :username), Keyword.get(basic_auth, :password)}
    end

    # Precedence, uniform across host/port/scheme: explicit opts > URI components
    # > default. (No env vars — those were removed in 0.3.0.)
    defp get_hostname_and_port(opts) do
      parsed_uri = parse_uri(opts)
      hostname = Keyword.get(opts, :hostname) || parsed_uri.host || "localhost"
      port = Keyword.get(opts, :port) || parsed_uri.port || @default_port
      {hostname, port}
    end

    defp get_schema(opts) do
      Keyword.get(opts, :scheme) || parse_uri(opts).scheme || "bolt+s"
    end

    defp parse_uri(opts) do
      opts |> Keyword.get(:uri) |> to_string() |> URI.parse()
    end

    def get_versions(opts) do
      case Keyword.get(opts, :versions) do
        nil ->
          {:ok, Versions.latest_versions()}

        versions ->
          parse_versions(versions)
      end
    end

    # Versions.parse/1 raises on a malformed entry (e.g. "abc" -> ArgumentError,
    # "5" or "5.4.3" -> MatchError, an unrecognised shape like an atom or map ->
    # FunctionClauseError) — none of which are documented, so left uncaught they
    # crash the connect callback instead of returning the {:error, %Bolty.Error{}}
    # this module otherwise guarantees (see :missing_username, :unsupported_versions).
    defp parse_versions(versions) do
      {parsed, deprecated_float?} =
        Enum.map_reduce(versions, false, fn version, dep? ->
          {canonical, float?} = Versions.parse(version)
          {canonical, dep? or float?}
        end)

      if deprecated_float? do
        require Logger

        Logger.warning(
          "bolty: passing float Bolt versions to :versions is deprecated and will be " <>
            "removed; use strings like \"5.4\" (a float can't distinguish 5.10 from 5.1)."
        )
      end

      reject_unsupported_versions(versions, parsed)
    rescue
      e ->
        {:error,
         Bolty.Error.wrap(Bolty.Client, %{
           code: :invalid_versions,
           message: "invalid :versions #{inspect(versions)}: #{Exception.message(e)}"
         })}
    end

    # bolty only ever negotiates versions it actually implements — a version
    # that isn't in Versions.available_versions() (e.g. a pre-5.0 Bolt version,
    # or one bolty hasn't caught up to yet) must never reach the handshake
    # bytes: if a server somehow *did* accept it, bolty's own message/policy
    # code doesn't speak that dialect and would fail confusingly deep in
    # encode/decode instead of cleanly at connect. Unsupported entries are
    # dropped with a warning as long as at least one requested version is
    # actually supported; if none are, that's a config error, not a silent
    # fallback to bolty's defaults (the caller asked for something specific).
    #
    # `:versions` entries can be a plain {major, minor} or a documented
    # {major, minor..minor} range (one handshake slot offering several
    # minors at once). A range is classified minor-by-minor rather than as
    # one opaque unit: if every minor in it is still supported it's kept
    # compactly as a range, if only some are it's kept as the individual
    # still-supported minors (e.g. after a future floor bump drops the low
    # end of a range a caller configured), and only a range with no
    # supported minors at all is dropped entirely.
    defp reject_unsupported_versions(raw_versions, parsed_versions) do
      supported = Versions.available_versions()
      classified = Enum.map(parsed_versions, &classify_version(&1, supported))

      kept = Enum.flat_map(classified, & &1.kept)
      dropped = Enum.flat_map(classified, & &1.dropped)

      cond do
        kept == [] ->
          {:error,
           Bolty.Error.wrap(Bolty.Client, %{
             code: :unsupported_versions,
             message:
               "none of the requested :versions #{inspect(raw_versions)} are supported by " <>
                 "bolty; supported versions are " <>
                 Enum.map_join(supported, ", ", &Versions.format/1)
           })}

        dropped != [] ->
          require Logger

          Logger.warning(
            "bolty: dropping unsupported Bolt version(s) " <>
              "#{Enum.map_join(dropped, ", ", &Versions.format/1)} from :versions " <>
              "(requested #{inspect(raw_versions)}) — bolty only supports " <>
              Enum.map_join(supported, ", ", &Versions.format/1)
          )

          {:ok, pad_and_sort(kept)}

        true ->
          {:ok, pad_and_sort(kept)}
      end
    end

    defp classify_version({_major, minor} = canonical, supported) when is_integer(minor) do
      if canonical in supported do
        %{kept: [canonical], dropped: []}
      else
        %{kept: [], dropped: [canonical]}
      end
    end

    defp classify_version({major, %Range{} = range}, supported) do
      {kept_minors, dropped_minors} =
        range |> Enum.to_list() |> Enum.split_with(&({major, &1} in supported))

      case {kept_minors, dropped_minors} do
        {_, []} ->
          %{kept: [{major, range}], dropped: []}

        {[], _} ->
          %{kept: [], dropped: Enum.map(dropped_minors, &{major, &1})}

        {kept, dropped} ->
          # Only 4 handshake slots exist in total (see pad_and_sort/1), so a
          # partially-supported range must stay as compact as possible rather
          # than exploding into one slot per surviving minor — re-coalesce any
          # contiguous survivors back into range slot(s) with the same logic
          # latest_versions/0 uses to build the default offer.
          recompacted =
            kept
            |> Enum.map(&{major, &1})
            |> Enum.sort(&>=/2)
            |> Versions.rangeify()

          %{kept: recompacted, dropped: Enum.map(dropped, &{major, &1})}
      end
    end

    defp pad_and_sort(versions) do
      (versions ++ [{0, 0}, {0, 0}, {0, 0}]) |> Enum.take(4) |> Enum.sort(&>=/2)
    end
  end

  def connect(%Config{} = config) do
    with {:ok, client} <- do_connect(config) do
      handshake(client, config)
    end
  end

  def connect(opts) when is_list(opts) do
    with {:ok, config} <- Config.new(opts) do
      connect(config)
    end
  end

  def do_connect(config) do
    client = %__MODULE__{sock: nil, bolt_version: nil, recv_timeout: config.recv_timeout}

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
         response when is_binary(response) <- recv_packets(client, config.connect_timeout),
         {major, minor} <- decode_version(response) do
      case {major, minor} do
        {0, 0} -> {:error, Bolty.Error.wrap(__MODULE__, :version_negotiation_error)}
        version -> {:ok, %{client | bolt_version: version}}
      end
    else
      {:error, %Bolty.Error{}} = error -> error
      {:error, reason} -> {:error, wrap_connect_error(reason)}
      _ -> {:error, Bolty.Error.wrap(__MODULE__, :version_negotiation_error)}
    end
  end

  def prepare_generic_messages(_bolt_version, messages) do
    MessageDecoder.prepare_generic(__MODULE__, messages)
  end

  def send_hello(client, fields) do
    payload = HelloMessage.encode(client.bolt_version, [{:policy, client.policy} | fields])

    send_and_recv(client, payload, &__MODULE__.prepare_generic_messages/2)
  end

  def send_logon(client, fields) do
    payload = LogonMessage.encode(client.bolt_version, fields)

    send_and_recv(client, payload, &__MODULE__.prepare_generic_messages/2)
  end

  def send_run(client, query, parameters, extra_parameters) do
    payload =
      RunMessage.encode(client.bolt_version, query, parameters, extra_parameters, client.policy)

    send_and_recv(client, payload, &RunMessage.prepare_messages/2)
  end

  def send_pull(client, extra_parameters) do
    payload = PullMessage.encode(client.bolt_version, extra_parameters)

    send_and_recv(client, payload, &PullMessage.prepare_messages/2)
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

    # Split on top-level `;` only — the splitter is aware of string literals,
    # comments, and backtick identifiers, so a `;` hiding inside any of those
    # does not break the batch. See `Bolty.Utils.StatementSplitter`.
    statements = Bolty.Utils.StatementSplitter.split(statement)

    Enum.reduce_while(statements, {:ok, []}, fn statement, {:ok, acc} ->
      case Bolty.Client.run_statement(client, statement, parameters, extra_parameters) do
        {:ok, result} -> {:cont, {:ok, [result | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  def send_begin(client, extra_parameters) do
    payload = BeginMessage.encode(client.bolt_version, extra_parameters)

    send_and_recv(client, payload, &__MODULE__.prepare_generic_messages/2)
  end

  def send_commit(client) do
    payload = CommitMessage.encode(client.bolt_version)

    send_and_recv(client, payload, &__MODULE__.prepare_generic_messages/2)
  end

  def send_rollback(client) do
    payload = RollbackMessage.encode(client.bolt_version)

    send_and_recv(client, payload, &__MODULE__.prepare_generic_messages/2)
  end

  def send_reset(client) do
    payload = ResetMessage.encode(client.bolt_version)

    send_and_recv(client, payload, &__MODULE__.prepare_generic_messages/2)
  end

  def send_discard(client, extra_parameters) do
    payload = DiscardMessage.encode(client.bolt_version, extra_parameters)

    send_and_recv(client, payload, &DiscardMessage.prepare_messages/2)
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

    send_and_recv(client, payload, &__MODULE__.prepare_generic_messages/2)
  end

  # Keepalive for idle pooled connections (see `Connection.ping/1`). RESET is a
  # single message round-trip — cheaper than a RUN/PULL and with no query
  # planning — and doubles as a liveness check: the server replies SUCCESS on a
  # healthy connection. It clears any server-side state, which is exactly what we
  # want on an idle connection between checkouts.
  def send_ping(client) do
    case send_reset(client) do
      {:ok, _} -> {:ok, true}
      _ -> {:error, :db_ping_failed}
    end
  end

  defp decode_version(<<0, 0, minor::unsigned-integer, major::unsigned-integer>>)
       when is_integer(major) and is_integer(minor) do
    {major, minor}
  end

  defp decode_version(_other), do: :error

  def send_packet(client, payload) do
    send_data(client, payload)
  end

  # Send an already-encoded message and read the response with the given
  # `prepare_messages/2` interpreter. The common body of the `send_*` helpers;
  # `send_goodbye/1` is the exception (it tears the port down on `:closed`).
  defp send_and_recv(client, payload, prepare_messages) do
    with :ok <- send_packet(client, payload) do
      recv_packets(client, prepare_messages, client.recv_timeout)
    end
  end

  def send_data(%{sock: {sock_mod, sock}}, data) do
    sock_mod.send(sock, data)
  end

  def recv_packets(client, timeout) do
    case recv_data(client, timeout) do
      {:ok, response} ->
        response

      {:error, reason} ->
        {:error, wrap_connect_error(reason)}
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

      # get_chunk_size/get_chunk already wrap a socket :timeout (and any other
      # recv error) into a %Bolty.Error{code: :timeout}; the caller tears the
      # connection down rather than reuse a desynced one.
      {:error, _} = error ->
        error
    end
  end

  defp get_next_message(client, timeout) do
    with {:ok, message_binary} <- read_chunks(client, timeout, <<>>) do
      decode_message(message_binary)
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
