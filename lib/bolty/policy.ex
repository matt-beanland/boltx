# SPDX-FileCopyrightText: 2024 bolty contributors
# SPDX-License-Identifier: Apache-2.0

defmodule Bolty.Policy do
  @moduledoc """
  Resolved driver behaviour for a single connection.

  Produced by `Bolty.Policy.Resolver` from the negotiated Bolt version (and
  optionally the HELLO response metadata), then stashed on the connection state
  and threaded into every pack/unpack/message call. Code pattern-matches on
  policy fields and never reads a Bolt or server version directly.

  Policy is an internal distillation of negotiated facts, not a user-facing
  configuration surface. Users influence policy by passing connection options
  (e.g. constraining `:versions` at negotiation); the resolver responds
  accordingly.

  See `.agent-notes/policy-design.md` for the authoritative design.
  """

  @typedoc """
  DateTime encoding dialect.

    * `:legacy` — emit legacy struct tags (0x46/0x66). Required for Bolt 4.x
      wire regardless of server version.
    * `:evolved` — emit evolved struct tags (0x49/0x69). Required for Bolt 5.x.
  """
  @type datetime :: :legacy | :evolved

  @typedoc """
  HELLO wire field name for disabled notification categories/classifications.

    * `:notifications_disabled_categories` — Bolt ≤ 5.5
    * `:notifications_disabled_classifications` — Bolt 5.6+ (spec rename)
  """
  @type notifications_field ::
          :notifications_disabled_categories | :notifications_disabled_classifications

  @type t :: %__MODULE__{
          datetime: datetime(),
          notifications_field: notifications_field(),
          gql_errors: boolean()
        }

  # defaults reflect the lowest supported Bolt version (5.0)
  defstruct datetime: :evolved,
            notifications_field: :notifications_disabled_categories,
            gql_errors: false
end
