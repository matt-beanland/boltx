# SPDX-FileCopyrightText: 2025 bolty contributors
# SPDX-License-Identifier: Apache-2.0

defmodule Bolty.TestDerivationStruct do
  @derive [{Bolty.PackStream.Packer, fields: [:foo]}]
  defstruct foo: "bar", name: "Hugo Weaving"
end
