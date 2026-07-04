# SPDX-FileCopyrightText: 2024 bolty contributors
# SPDX-License-Identifier: Apache-2.0

defmodule Bolty do
  @moduledoc """
  Bolt driver for Elixir.
  """

  @type conn() :: DBConnection.conn()

  @typedoc """
  The basic authentication scheme relies on traditional username and password

  * `:username` - Username (required)

  * `:password` - Password (default: `nil`)
  """
  @type basic_auth() ::
          {:username, String.t()}
          | {:password, String.t() | nil}

  @type start_option() ::
          {:uri, String.t()}
          | {:hostname, String.t()}
          | {:port, :inet.port_number()}
          | {:scheme, :inet.port_number()}
          | {:versions, list(String.t() | float())}
          | {:auth, basic_auth()}
          | {:user_agent, String.t()}
          | {:notifications_minimum_severity, String.t()}
          | {:notifications_disabled_categories, list(String.t())}
          | {:ssl, boolean()}
          | {:ssl_opts, [:ssl.tls_client_option()]}
          | {:connect_timeout, timeout()}
          | {:recv_timeout, timeout()}
          | {:socket_options, [:gen_tcp.connect_option()]}
          | DBConnection.start_option()

  @type option :: %{
          bookmarks: list(),
          mode: String.t(),
          db: String.t() | nil,
          tx_metadata: map() | nil
        }

  @doc """
  Starts the connection process and connects to a Bolt/Neo4j server.

  ## Options

  * `:uri` - Connection URI, of the form `<SCHEME>://<HOST>[:<PORT>[?policy=<POLICY-NAME>]]`.
   Explicit `:hostname`, `:port` and `:scheme` options take priority over the
   corresponding URI components.

  * `:hostname` - Server hostname (default: `"localhost"`)

  * `:port` - Server port (default: `7687`)

  * `:scheme` - Is one among neo4j, neo4j+s, neo4j+ssc, bolt, bolt+s, bolt+ssc (default: bolt+s).

  * `:versions` - List of Bolt versions to offer during negotiation, as strings
   (`["5.4", "6.0"]`) or `{major, minor..minor}` range tuples (`[{5, 6..8}]`).
   Floats (`[5.4]`) are **deprecated** — they can't distinguish `5.10` from `5.1`
   — and are still accepted with a one-time warning. (Default: the latest
   supported versions.)

  * `:auth` - The basic authentication scheme

  * `:user_agent` - Optionally override the default user agent name. (Default: 'bolty/<version>')

  * `:notifications_minimum_severity` - Set the minimum severity for notifications the server
   should send to the client. Disabling severities allows the server to skip analysis for those,
  which can speed up query execution. (default: nil) _New in neo4j v5.7 and Bolt v5.2_

  * `:notifications_disabled_categories` - Set categories of notifications the server should not
   send to the client. Disabling categories allows the server to skip analysis for those, which
  can speed up query execution. (default: nil) _New in neo4j v5.7 and Bolt v5.2_

  * `:connect_timeout` - Socket connect timeout in milliseconds (default:
      `15_000`)

  * `:recv_timeout` - Per-read timeout in milliseconds for post-connect protocol
      reads (default: `15_000`). This is a socket-inactivity timeout: it fires
      only if the server sends *no* bytes for this long, and the window resets on
      each chunk received, so streaming a large result is unaffected. A read that
      times out is surfaced as `{:error, %Bolty.Error{code: :timeout}}` and the
      connection is disconnected. Can be overridden per query via the same option
      to `query/4`; set to `:infinity` for queries that may compute for a long
      time before returning any data.

  * `:ssl` - Set to `true` if SSL should be used (default: `true`)

  * `:ssl_opts` - A list of SSL options, see `:ssl.connect/2` (default: `[verify: :verify_none]`)

  The given options are passed down to DBConnection, some of the most commonly used ones are
   documented below:

  * `:after_connect` - A function to run after the connection has been established, either a
      1-arity fun, a `{module, function, args}` tuple, or `nil` (default: `nil`)

  * `:pool` - The pool module to use, defaults to built-in pool provided by DBconnection

  * `:pool_size` - The size of the pool
  """
  @spec start_link([start_option()]) :: {:ok, pid()} | {:error, Bolty.Error.t()}
  def start_link(options) do
    DBConnection.start_link(Bolty.Connection, options)
  end

  @doc """
  Returns a supervisor child specification for a DBConnection pool.
  """
  @spec child_spec([start_option()]) :: :supervisor.child_spec()
  def child_spec(options) do
    DBConnection.child_spec(Bolty.Connection, options)
  end

  @doc """
  Executes a single query and returns the result.

  Returns `{:ok, %Bolty.Response{}}` on success. On failure it returns
  `{:error, %Bolty.Error{}}` — every driver-side failure (connection, TLS,
  version negotiation, and Neo4j server errors) is surfaced as a `Bolty.Error`,
  so callers can match a single error shape. Pool checkout/timeout failures may
  additionally surface as `DBConnection.ConnectionError`.

  ## Options

  * `:db` - Target database for multi-database routing (default: server default).

  * `:recv_timeout` - Overrides the connection's `:recv_timeout` for this query
      (see `start_link/1`). Pass `:infinity` for a query expected to run longer
      than the connection default before returning data.

  ## Examples

  ```elixir
  {:ok, result} = Bolty.query(conn, "MATCH (n) RETURN n LIMIT 1")

  {:ok, people} = Bolty.query(conn, "MATCH (n:PERSON) RETURN n", %{}, [db: "mydb"])
  ```
  """
  def query(conn, statement, params \\ %{}, opts \\ []) do
    formatted_params =
      params
      |> Enum.map(&format_param/1)
      |> Enum.map(fn {k, {:ok, value}} -> {k, value} end)
      |> Map.new()

    extra =
      opts
      |> Keyword.take([:bookmarks, :mode, :db, :tx_metadata])
      # Convert to map
      |> Enum.into(%{})

    query = %Bolty.Query{statement: statement, extra: extra}

    do_query(conn, query, formatted_params, opts)
  end

  @doc """
  Executes a single query and returns the result.

  ## Examples

  ```elixir
  result = Bolty.query!(conn, "MATCH (n) RETURN n LIMIT 1")

  people = Bolty.query!(conn, "MATCH (n:PERSON) RETURN n", %{}, [db: "mydb"])
  ```
  """
  def query!(conn, statement, params \\ %{}, opts \\ []) do
    case query(conn, statement, params, opts) do
      {:ok, result} -> result
      {:error, exception} -> raise exception
    end
  end

  def query_many(conn, statement, params \\ %{}, opts \\ []) do
    formatted_params =
      params
      |> Enum.map(&format_param/1)
      |> Enum.map(fn {k, {:ok, value}} -> {k, value} end)
      |> Map.new()

    queries = %Bolty.Queries{statement: statement}
    do_query(conn, queries, formatted_params, opts)
  end

  def query_many!(conn, statement, params \\ %{}, opts \\ []) do
    case query_many(conn, statement, params, opts) do
      {:ok, result} -> result
      {:error, exception} -> raise exception
    end
  end

  @spec transaction(conn, (DBConnection.t() -> result), [DBConnection.option()], map()) ::
          {:ok, result} | {:error, any}
        when result: var
  def transaction(conn, fun, opts \\ [], extra_parameters \\ %{}) do
    DBConnection.transaction(conn, fun, opts ++ [extra_parameters: extra_parameters])
  end

  @spec rollback(DBConnection.t(), any()) :: no_return()
  defdelegate rollback(conn, reason), to: DBConnection

  @doc """
  Returns metadata about the negotiated connection.

  Can be called with the `conn` passed into a `transaction/3` callback or any
  checked-out connection.

  ## Example

  ```elixir
  Bolty.transaction(Bolt, fn conn ->
    Bolty.connection_info(conn)
    # => %{bolt_version: "5.8", server_version: "Neo4j/5.26.27", policy: %Bolty.Policy{...}}
  end)
  ```
  """
  @spec connection_info(conn()) :: %{
          bolt_version: String.t(),
          server_version: String.t(),
          policy: Bolty.Policy.t()
        }
  def connection_info(conn) do
    {:ok, _, info} = DBConnection.prepare_execute(conn, %Bolty.ConnectionInfo{}, %{})
    info
  end

  # Wrap the round-trip in a `[:bolty, :query]` telemetry span so operators get
  # `:start`/`:stop`/`:exception` events with duration, statement, and outcome
  # without instrumenting every call site. See `guides/telemetry.md`.
  #
  # This span is for the EAGER path only: `:telemetry.span` closes when the fun
  # returns, and here that means the full result is materialised. Lazy streaming
  # (#59, via handle_declare/handle_fetch) must NOT reuse this — a cursor returns
  # before any rows are pulled, so the span would time only RUN and would stuff
  # the whole materialised result into `:result`. Streaming needs its own
  # start-on-declare / stop-on-deallocate instrumentation carrying row counts.
  defp do_query(conn, query, params, options) do
    metadata = %{
      db_system: "neo4j",
      db_statement: statement(query),
      db_instance: options[:db]
    }

    # `:telemetry.span` fires `:exception` (and reraises) if the fun raises/exits;
    # for the `{:error, _}` return we flag a coarse `:result` status and stash the
    # error so tracers can set span status without us holding the whole result.
    :telemetry.span([:bolty, :query], metadata, fn ->
      case DBConnection.prepare_execute(conn, query, params, options) do
        {:ok, _query, result} ->
          {{:ok, result}, Map.put(metadata, :result, :ok)}

        # prepare_execute always surfaces failures as an exception struct
        # (%Bolty.Error{} or %DBConnection.ConnectionError{}).
        {:error, error} = failure ->
          {failure, metadata |> Map.put(:result, :error) |> Map.put(:error, error)}
      end
    end)
  end

  defp statement(%Bolty.Query{statement: statement}), do: statement
  defp statement(%Bolty.Queries{statement: statement}), do: statement

  defp format_param({name, value}), do: {name, {:ok, value}}
end
