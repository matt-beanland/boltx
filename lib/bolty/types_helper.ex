# SPDX-FileCopyrightText: 2025 bolty contributors
# SPDX-License-Identifier: Apache-2.0

defmodule Bolty.TypesHelper do
  @moduledoc false

  @doc """
  Decompose an amount seconds into the tuple {hours, minutes, seconds}
  """
  @spec decompose_in_hms(integer()) :: {integer(), integer(), integer()}
  def decompose_in_hms(seconds) do
    [{minutes, seconds}, {hours, _}, _] =
      [3600, 60]
      |> Enum.reduce([{0, seconds}], fn
        divisor, acc ->
          {_, num} = hd(acc)
          [{div(num, divisor), rem(num, divisor)} | acc]
      end)

    {hours, minutes, seconds}
  end

  @doc """
  Convert an amount of seconds in a +hours:minutes offset
  """
  @spec formated_time_offset(integer()) :: String.t()
  def formated_time_offset(offset_seconds) do
    {hours, minutes, _} = offset_seconds |> abs() |> decompose_in_hms()
    get_sign_string(offset_seconds) <> format_time_part(hours) <> ":" <> format_time_part(minutes)
  end

  defp get_sign_string(number) when number >= 0 do
    "+"
  end

  defp get_sign_string(_) do
    "-"
  end

  defp format_time_part(time_part) when time_part < 10 do
    "0" <> Integer.to_string(time_part)
  end

  defp format_time_part(time_part) do
    Integer.to_string(time_part)
  end

  @period_prefix "P"
  @time_prefix "T"

  @year_suffix "Y"
  @month_suffix "M"
  @week_suffix "W"
  @day_suffix "D"
  @hour_suffix "H"
  @minute_suffix "M"
  @second_suffix "S"

  @doc """
  Create a Duration struct from the given parameters.
  Note that this can be lossy, as Elixir Duration doesn't have nanosecond precision.
  """

  @spec create_duration(integer(), integer(), integer(), integer()) :: Duration.t()
  def create_duration(months, days, seconds, nanoseconds) do
    Duration.new!(
      year: div(months, 12),
      month: rem(months, 12),
      day: days,
      hour: div(seconds, 3_600),
      minute: div(rem(seconds, 3_600), 60),
      second: rem(seconds, 60),
      microsecond: {div(nanoseconds, 1_000), 6}
    )
  end

  @doc """
  Formats an Elixir `Duration` (as decoded from a Neo4j duration) as an
  ISO-8601 duration string, matching Neo4j's own `toString(duration)`
  ([Cypher temporal durations](https://neo4j.com/docs/cypher-manual/current/syntax/temporal/#cypher-temporal-durations)):

    * whole seconds render without a fractional part (`PT65S`, not `PT65.0S`);
    * a fractional second renders with no trailing zeros (`PT5.5S`, `PT0.123456S`);
    * negative components are preserved (`PT-30S`);
    * an all-zero duration renders as `PT0S`.

  Returns `{:ok, string}`, or `{:error, term}` for anything that isn't a
  well-formed `Duration`.
  """
  @spec format_duration(Duration.t()) :: {:ok, String.t()} | {:error, any()}
  def format_duration(
        %Duration{
          year: y,
          month: m,
          day: d,
          hour: h,
          minute: mm,
          second: s,
          microsecond: us
        } = duration
      )
      when is_integer(y) and is_integer(m) and is_integer(d) and is_integer(h) and
             is_integer(mm) and is_integer(s) and is_tuple(us) do
    body = format_date(duration) <> format_time(duration)

    # An all-zero duration has no components; Neo4j renders it as "PT0S".
    formatted =
      case body do
        "" -> @period_prefix <> @time_prefix <> "0" <> @second_suffix
        body -> @period_prefix <> body
      end

    {:ok, formatted}
  end

  def format_duration(param) do
    {:error, param}
  end

  # Date components: emit each non-zero part, negatives included (e.g. "-2D").
  @spec format_date(Duration.t()) :: String.t()
  defp format_date(%Duration{year: y, month: m, week: w, day: d}) do
    format_duration_part(y, @year_suffix) <>
      format_duration_part(m, @month_suffix) <>
      format_duration_part(w, @week_suffix) <> format_duration_part(d, @day_suffix)
  end

  # Time components — a "T" section, present only when at least one time field is
  # non-zero (so a pure-date duration carries no "T"). Seconds combine the whole
  # and microsecond fields (see format_seconds/2).
  @spec format_time(Duration.t()) :: String.t()
  defp format_time(%Duration{hour: h, minute: m, second: s, microsecond: {us, _precision}})
       when h != 0 or m != 0 or s != 0 or us != 0 do
    @time_prefix <>
      format_duration_part(h, @hour_suffix) <>
      format_duration_part(m, @minute_suffix) <>
      format_seconds(s, us)
  end

  defp format_time(_) do
    ""
  end

  # A whole (integer) date/time component: non-zero -> "<n><suffix>", else "".
  @spec format_duration_part(integer(), String.t()) :: String.t()
  defp format_duration_part(part, suffix) when is_integer(part) and part != 0 do
    "#{part}#{suffix}"
  end

  defp format_duration_part(_, _) do
    ""
  end

  # Seconds + microseconds as one ISO-8601 seconds field with no trailing zeros:
  # 65,0 -> "65S"; 5,500000 -> "5.5S"; 0,123456 -> "0.123456S"; -30,0 -> "-30S".
  # Omitted entirely when both are zero (the S part is dropped when other time
  # components already carry the duration, e.g. "PT5M").
  @spec format_seconds(integer(), integer()) :: String.t()
  defp format_seconds(0, 0), do: ""

  defp format_seconds(s, us) do
    total_us = s * 1_000_000 + us
    sign = if total_us < 0, do: "-", else: ""
    abs_us = abs(total_us)
    whole = div(abs_us, 1_000_000)
    frac = rem(abs_us, 1_000_000)

    digits =
      if frac == 0 do
        Integer.to_string(whole)
      else
        frac_str =
          frac |> Integer.to_string() |> String.pad_leading(6, "0") |> String.trim_trailing("0")

        "#{whole}.#{frac_str}"
      end

    "#{sign}#{digits}#{@second_suffix}"
  end
end
