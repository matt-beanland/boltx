defmodule Bolty.TestDerivationStruct do
  @derive [{Bolty.PackStream.Packer, fields: [:foo]}]
  defstruct foo: "bar", name: "Hugo Weaving"
end
