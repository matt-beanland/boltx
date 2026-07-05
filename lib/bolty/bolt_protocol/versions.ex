# SPDX-FileCopyrightText: 2024 bolty contributors
# SPDX-License-Identifier: Apache-2.0

defmodule Bolty.BoltProtocol.Versions do
  @moduledoc false

  # Versions are represented internally as `{major, minor}` integer tuples, not
  # floats: a float can't distinguish 5.10 from 5.1, and tuple term-ordering
  # compares as versions (`{5, 10} > {5, 6}`). Floats are accepted at the public
  # `:versions` boundary for backwards compatibility (see `parse/1`) but never
  # flow further in.
  @available_bolt_versions [
    {5, 0},
    {5, 1},
    {5, 2},
    {5, 3},
    {5, 4},
    {5, 6},
    {5, 7},
    {5, 8},
    {6, 0}
  ]

  @type version :: {non_neg_integer(), non_neg_integer()}
  @type version_range :: {non_neg_integer(), Range.t()}

  @spec available_versions() :: [version()]
  def available_versions() do
    @available_bolt_versions
  end

  @spec latest_versions() :: [version() | version_range()]
  def latest_versions() do
    ((available_versions() |> Enum.sort(&>=/2) |> rangeify()) ++ [{0, 0}, {0, 0}, {0, 0}])
    |> Enum.take(4)
  end

  @doc """
  Normalise a user-supplied `:versions` entry to the internal `{major, minor}`
  form. Accepts the string form (`"5.4"`), an explicit `{major, minor}` /
  `{major, minor..minor}` tuple, or — deprecated — a float (`5.4`) or bare major
  integer (`5`). Returns `{version, deprecated?}` so the caller can emit a single
  deprecation warning.
  """
  @spec parse(String.t() | float() | integer() | version() | version_range()) ::
          {version() | version_range(), boolean()}
  def parse(version) when is_binary(version) do
    [major, minor] = version |> String.split(".") |> Enum.map(&String.to_integer/1)
    {{major, minor}, false}
  end

  def parse(version) when is_float(version) do
    [major, minor] =
      version |> Float.to_string() |> String.split(".") |> Enum.map(&String.to_integer/1)

    {{major, minor}, true}
  end

  def parse(version) when is_integer(version), do: {{version, 0}, true}

  def parse({major, minor} = version) when is_integer(major) and is_integer(minor),
    do: {version, false}

  def parse({major, %Range{}} = version) when is_integer(major), do: {version, false}

  @doc "Render a `{major, minor}` version as its public string form, e.g. `\"5.8\"`."
  @spec format(version()) :: String.t()
  def format({major, minor}), do: "#{major}.#{minor}"

  @spec to_bytes(version() | version_range()) :: binary()
  def to_bytes({major, minor}) when is_integer(minor) do
    <<0, 0>> <> <<minor, major>>
  end

  def to_bytes({major, %Range{} = minor_range}) do
    minor = List.last(Range.to_list(minor_range))
    previous = Range.size(minor_range) - 1
    <<0>> <> <<previous, minor, major>>
  end

  @spec rangeify([version()]) :: [version() | version_range()]
  def rangeify(list) when is_list(list) do
    list
    |> Enum.reduce([], fn {major, minor} = value, acc ->
      cond do
        acc == [] ->
          [value]

        major < 4 ->
          [value | acc]

        major == 4 and minor < 3 ->
          [value | acc]

        true ->
          [{prev_major, prev_minor_or_range} | tail] = acc

          cond do
            major < prev_major ->
              [value | acc]

            is_integer(prev_minor_or_range) ->
              if minor + 1 == prev_minor_or_range do
                [{prev_major, Range.new(minor, prev_minor_or_range)} | tail]
              else
                [value | acc]
              end

            true ->
              if minor + 1 == prev_minor_or_range.first do
                [
                  {prev_major, Range.new(minor, List.last(Range.to_list(prev_minor_or_range)))}
                  | tail
                ]
              else
                [value | acc]
              end
          end
      end
    end)
    |> Enum.reverse()
  end
end
