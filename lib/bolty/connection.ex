# SPDX-FileCopyrightText: 2024 bolty contributors
# SPDX-License-Identifier: Apache-2.0

defmodule Bolty.Connection do
  @moduledoc false
  use DBConnection

  import Bolty.BoltProtocol.ServerResponse

  alias Bolty.BoltProtocol.Versions
  alias Bolty.Client
  alias Bolty.Policy
  alias Bolty.Response

  defstruct [
    :client,
    :server_version,
    :hints,
    :connection_id,
    :policy,
    in_transaction: false,
    # qids of declared stream cursors that still have records pending
    # server-side. handle_fetch removes a qid once its result is drained
    # (has_more false); handle_deallocate DISCARDs only what remains here, so a
    # fully-consumed stream isn't DISCARDed against an already-closed qid.
    open_cursors: %{}
  ]

  @default_fetch_size 1000

  @impl true
  def connect(opts) do
    start = System.monotonic_time()

    with {:ok, config} <- Client.Config.new(opts),
         {:ok, %Client{} = client} <- Client.connect(config) do
      # Resolve a preliminary policy from bolt_version alone so that HELLO
      # message construction can use policy fields (e.g. notifications_field)
      # rather than reading bolt_version directly. The final policy is resolved
      # again below from the full HELLO response metadata; all current
      # dimensions depend only on bolt_version so both calls produce the same
      # result in practice.
      preliminary_policy = Policy.Resolver.resolve(client.bolt_version, %{})
      client_with_policy = %{client | policy: preliminary_policy}

      with {:ok, response_server_metadata} <- do_init(client_with_policy, opts, config) do
        policy = Policy.Resolver.resolve(client.bolt_version, response_server_metadata)
        state = get_server_metadata_state(response_server_metadata)
        new_state = %__MODULE__{state | client: %{client | policy: policy}, policy: policy}

        :telemetry.execute(
          [:bolty, :connect],
          %{duration: System.monotonic_time() - start},
          %{
            db_system: "neo4j",
            bolt_version: Versions.format(client.bolt_version),
            server_version: new_state.server_version,
            connection_id: new_state.connection_id
          }
        )

        {:ok, new_state}
      end
    end
  end

  @impl true
  def handle_begin(opts, %__MODULE__{client: client} = state) do
    extra_parameters = opts[:extra_parameters] || %{}

    case Client.send_begin(client, extra_parameters) do
      {:ok, _} -> {:ok, :began, %{state | in_transaction: true}}
      {:error, error} -> {:disconnect, error, state}
    end
  end

  @impl true
  def handle_commit(_, %__MODULE__{in_transaction: false} = state) do
    # A FAILURE earlier in this transaction already aborted it server-side and the
    # connection was RESET back to a usable state (see execute/4). There is no
    # server-side transaction left to commit, and sending COMMIT now would be
    # rejected (Request.Invalid) and needlessly disconnect a healthy connection.
    # Report the aborted-transaction status (:error) so the caller learns the
    # commit did not happen, without tearing the connection down.
    {:error, state}
  end

  def handle_commit(_, %__MODULE__{client: client} = state) do
    case Client.send_commit(client) do
      {:ok, _} -> {:ok, :committed, %{state | in_transaction: false}}
      {:error, error} -> {:disconnect, error, state}
    end
  end

  @impl true
  def handle_rollback(_, %__MODULE__{in_transaction: false} = state) do
    # The transaction was already aborted by an earlier FAILURE and the connection
    # RESET back to a usable state (see execute/4); there is nothing left to roll
    # back. Sending ROLLBACK now would be rejected (Request.Invalid) and disconnect
    # a healthy connection, so just report a successful rollback.
    {:ok, :rolledback, state}
  end

  def handle_rollback(_, %__MODULE__{client: client} = state) do
    case Client.send_rollback(client) do
      {:ok, _} -> {:ok, :rolledback, %{state | in_transaction: false}}
      {:error, error} -> {:disconnect, error, state}
    end
  end

  @impl true
  def handle_execute(%Bolty.ConnectionInfo{} = query, _params, _opts, state) do
    result = %{
      bolt_version: Versions.format(state.client.bolt_version),
      server_version: state.server_version,
      policy: state.client.policy
    }

    {:ok, query, result, state}
  end

  def handle_execute(query, params, opts, state) do
    case execute(query, params, opts, state) do
      {:ok, _} = result ->
        result(result, query, state)

      other ->
        other
    end
  end

  @impl true
  def disconnect(_reason, state) do
    :telemetry.execute(
      [:bolty, :disconnect],
      %{system_time: System.system_time()},
      %{db_system: "neo4j", connection_id: state.connection_id}
    )

    Client.send_goodbye(state.client)
    Client.disconnect(state.client)
  end

  @impl true
  def checkout(state) do
    {:ok, state}
  end

  @impl true
  def ping(state) do
    case Client.send_ping(state.client) do
      {:ok, true} ->
        {:ok, state}

      _ ->
        {:disconnect, Bolty.Error.wrap(__MODULE__, :db_ping_failed), state}
    end
  end

  @impl true
  def handle_prepare(query, _opts, state), do: {:ok, query, state}
  @impl true
  def handle_close(query, _opts, state), do: {:ok, query, state}
  # Declare a server-side cursor for lazy streaming (DBConnection.stream/4, via
  # Bolty.stream/3). Sends RUN only — no PULL — capturing the `qid` and `fields`
  # from the RUN SUCCESS. Must run inside a transaction (DBConnection.stream
  # enforces this); the explicit transaction is what makes the server assign a
  # qid, which subsequent PULL/DISCARD page against.
  @impl true
  def handle_declare(
        %Bolty.Query{statement: statement, extra: extra} = query,
        params,
        opts,
        state
      ) do
    %__MODULE__{client: client} = state
    fetch_size = Keyword.get(opts, :fetch_size, @default_fetch_size)

    case Client.send_run(client, statement, params, extra) do
      {:ok, run_success} ->
        qid = Map.get(run_success, "qid", -1)
        cursor = %{qid: qid, fields: Map.get(run_success, "fields", []), fetch_size: fetch_size}
        state = %{state | open_cursors: Map.put(state.open_cursors, qid, true)}
        {:ok, query, cursor, state}

      {:error, error} ->
        declare_or_fetch_failure(client, error, state)
    end
  end

  # Fetch the next batch: PULL {n: fetch_size, qid}. Each batch is surfaced as a
  # `%Bolty.Response{}` (its `results`/`records` are that batch; summary/stats/
  # bookmark land on the final batch's SUCCESS). `has_more` decides whether the
  # cursor continues (`:cont`) or is exhausted (`:halt`).
  @impl true
  def handle_fetch(_query, %{qid: qid, fields: fields, fetch_size: fetch_size}, _opts, state) do
    %__MODULE__{client: client} = state

    case Client.send_pull(client, %{n: fetch_size, qid: qid}) do
      {:ok, pull_result(success_data: success_data) = result_pull} ->
        response =
          Response.new(
            statement_result(result_run: %{"fields" => fields}, result_pull: result_pull)
          )

        if Map.get(success_data, "has_more", false) do
          {:cont, response, state}
        else
          {:halt, response, %{state | open_cursors: Map.delete(state.open_cursors, qid)}}
        end

      {:error, error} ->
        # Drop the qid first: after a FAILURE the recovery RESET clears the
        # server-side cursor, so handle_deallocate must not DISCARD it.
        declare_or_fetch_failure(client, error, %{
          state
          | open_cursors: Map.delete(state.open_cursors, qid)
        })
    end
  end

  # Release a cursor. Only DISCARD one still holding records server-side (early
  # termination); a fully-drained cursor's qid is already closed, so DISCARDing
  # it would error. Always drop it from the tracking map.
  @impl true
  def handle_deallocate(query, %{qid: qid}, _opts, state) do
    drained_state = %{state | open_cursors: Map.delete(state.open_cursors, qid)}

    if Map.has_key?(state.open_cursors, qid) do
      case Client.send_discard(state.client, %{n: -1, qid: qid}) do
        {:ok, _} -> {:ok, query, drained_state}
        {:error, error} -> {:disconnect, error, drained_state}
      end
    else
      {:ok, query, drained_state}
    end
  end

  @impl true
  def handle_status(_opts, %__MODULE__{in_transaction: true} = state), do: {:transaction, state}
  def handle_status(_opts, state), do: {:idle, state}

  defp execute(statement, params, opts, state) do
    %__MODULE__{client: client} = state

    # Per-query override of the connection-wide :recv_timeout. Applied to a local
    # copy only, so it governs this call (RUN/PULL) without leaking into the
    # pooled connection's state and affecting later queries.
    client =
      case Keyword.fetch(opts, :recv_timeout) do
        {:ok, recv_timeout} -> %{client | recv_timeout: recv_timeout}
        :error -> client
      end

    case Client.run_statement(client, statement, params) do
      {:ok, statement_result} ->
        {:ok, statement_result}

      # A recv timeout left the socket desynced (a late RUN/PULL response may still
      # arrive); RESET-recovery would read the wrong bytes, so tear the connection
      # down instead of returning it to the pool.
      {:error, %Bolty.Error{code: :timeout} = error} ->
        {:disconnect, error, state}

      {:error, %Bolty.Error{} = error} ->
        recover_from_failure(client, error, state)
    end
  rescue
    # An exception mid-execute (e.g. raised during recv after RUN was sent) can
    # leave unread RECORD/SUCCESS bytes on the socket that would poison the next
    # query on this pooled connection. Disconnect rather than return it to the
    # pool, and surface a %Bolty.Error{} instead of the raw exception. If the
    # raised exception is already a %Bolty.Error{} (e.g. a decode error thrown by
    # the unpacker), pass it through so its specific code/message reach the
    # caller rather than being flattened to `:execute_exception`.
    e ->
      error =
        case e do
          %Bolty.Error{} ->
            e

          _ ->
            Bolty.Error.wrap(__MODULE__, %{
              code: :execute_exception,
              message: Exception.message(e)
            })
        end

      {:disconnect, error, state}
  end

  # A statement FAILURE leaves the Bolt connection in the protocol's FAILED state.
  # Per the Bolt protocol the only way out is RESET — a ROLLBACK/COMMIT, or any
  # further statement, is IGNORED. We therefore RESET after *any* FAILURE, for *any*
  # error code, whether or not we are in a transaction. This recovers both:
  #
  #   * the in-transaction path — otherwise the trailing ROLLBACK is IGNORED and the
  #     connection is force-disconnected (noisy `:ignored` error), and
  #   * the bare-query path — otherwise the FAILED connection is returned to the pool
  #     and poisons every later checkout with `:ignored` until it churns.
  #
  # After a successful RESET there is no server-side transaction left, so clear
  # in_transaction; handle_rollback/handle_commit rely on that to avoid sending a
  # ROLLBACK/COMMIT that the now-recovered connection would reject. If RESET itself
  # fails — returning an error or raising — the connection is genuinely unusable,
  # so disconnect. Crucially we disconnect with the *original* query `error`: a
  # failed RESET must never mask what the caller was actually told went wrong.
  defp recover_from_failure(client, error, state) do
    case Client.send_reset(client) do
      {:ok, _} -> {:error, error, %{state | in_transaction: false}}
      {:error, _reset_error} -> {:disconnect, error, state}
    end
  rescue
    _ -> {:disconnect, error, state}
  end

  # Shared error handling for the streaming RUN (handle_declare) and PULL
  # (handle_fetch). A recv timeout leaves the socket desynced, so tear the
  # connection down; any other FAILURE follows the same RESET-recovery as the
  # eager path (see execute/4) so a bad streamed query doesn't poison the pooled
  # connection. Both return shapes ({:error, _, _} / {:disconnect, _, _}) are
  # valid for the declare and fetch callbacks.
  defp declare_or_fetch_failure(_client, %Bolty.Error{code: :timeout} = error, state) do
    {:disconnect, error, state}
  end

  defp declare_or_fetch_failure(client, %Bolty.Error{} = error, state) do
    recover_from_failure(client, error, state)
  end

  defp declare_or_fetch_failure(_client, error, state) do
    {:disconnect, error, state}
  end

  defp result(
         {:ok, statement_result() = statement_result},
         query,
         state
       ) do
    {:ok, query, Response.new(statement_result), state}
  end

  defp result(
         {:ok, statement_results},
         query,
         state
       )
       when is_list(statement_results) do
    {:ok, query,
     Enum.reduce(statement_results, [], fn result, acc ->
       [Response.new(result) | acc]
     end), state}
  end

  defp do_init(client, opts, config) do
    do_init(client.bolt_version, client, opts, config)
  end

  defp do_init(bolt_version, client, opts, config)
       when is_tuple(bolt_version) and bolt_version >= {5, 1} do
    with {:ok, response_hello} <- Client.send_hello(client, hello_fields(opts, config)),
         {:ok, _response_logon} <- Client.send_logon(client, opts) do
      {:ok, response_hello}
    end
  end

  defp do_init(bolt_version, client, opts, config) when is_tuple(bolt_version) do
    Client.send_hello(client, hello_fields(opts, config))
  end

  # Carry the resolved HELLO `routing` extras (server-side routing) alongside the
  # raw start opts. `nil` means routing is off, so the field is omitted entirely
  # and the connection stays a plain direct one. The user-facing boolean `:routing`
  # opt (if any) was already consumed by Config.new/1; here it's replaced by the
  # resolved `%{"address" => ...}` value the HELLO encoder sends verbatim.
  defp hello_fields(opts, %Client.Config{routing: nil}), do: opts

  defp hello_fields(opts, %Client.Config{routing: routing}),
    do: Keyword.put(opts, :routing, routing)

  defp get_server_metadata_state(response_metadata) do
    hints = Map.get(response_metadata, "hints", "")
    connection_id = Map.get(response_metadata, "connection_id", "")

    %__MODULE__{
      client: nil,
      server_version: response_metadata["server"],
      hints: hints,
      connection_id: connection_id
    }
  end
end
