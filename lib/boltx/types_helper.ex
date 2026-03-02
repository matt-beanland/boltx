defmodule Boltx.TypesHelper do
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
  Convert NaiveDateTime and timezone into a Calendar.DateTime
  Without losing microsecond data!
  """
  @spec datetime_with_micro(Calendar.naive_datetime(), String.t()) :: Calendar.datetime()
  def datetime_with_micro(%NaiveDateTime{} = naive_dt, timezone) do
    DateTime.from_naive!(naive_dt, timezone)
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
  Convert a %Duration in a cypher-compliant string.
  To know everything about duration format, please see:
  https://neo4j.com/docs/cypher-manual/current/syntax/temporal/#cypher-temporal-durations
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
    formated = format_date(duration) <> format_time(duration)

    param =
      case formated do
        "" -> ""
        formated_duration -> @period_prefix <> formated_duration
      end

    {:ok, param}
  end

  def format_duration(param) do
    {:error, param}
  end

  @spec format_date(Duration.t()) :: String.t()
  defp format_date(%Duration{year: y, month: m, week: w, day: d}) do
    format_duration_part(y, @year_suffix) <>
      format_duration_part(m, @month_suffix) <>
      format_duration_part(w, @week_suffix) <> format_duration_part(d, @day_suffix)
  end

  @spec format_time(Duration.t()) :: String.t()
  defp format_time(%Duration{
         hour: h,
         minute: m,
         second: s,
         microsecond: us
       })
       when h > 0 or m > 0 or s > 0 or us.microsecond > 0 do
    {seconds, nanoseconds} = cap_nanoseconds(s, us)
    nanoseconds_f = nanoseconds |> Integer.to_string() |> String.pad_leading(9, "0")
    seconds_f = "#{Integer.to_string(seconds)}.#{nanoseconds_f}" |> String.to_float()

    @time_prefix <>
      format_duration_part(h, @hour_suffix) <>
      format_duration_part(m, @minute_suffix) <>
      format_duration_part(seconds_f, @second_suffix)
  end

  defp format_time(_) do
    ""
  end

  @spec format_duration_part(number(), String.t()) :: String.t()
  defp format_duration_part(duration_part, suffix)
       when duration_part > 0 and is_bitstring(suffix) do
    "#{stringify_number(duration_part)}#{suffix}"
  end

  defp format_duration_part(_, _) do
    ""
  end

  @spec stringify_number(number()) :: String.t()
  defp stringify_number(number) when is_integer(number) do
    Integer.to_string(number)
  end

  defp stringify_number(number) do
    Float.to_string(number)
  end

  @spec cap_nanoseconds(integer(), tuple()) :: {integer(), integer()}
  defp cap_nanoseconds(s, us) when is_integer(s) and is_tuple(us) do
    {microseconds, _precision} = us
    ns = microseconds * 1000
    seconds_ = s + div(ns, 1_000_000_000)
    nanoseconds_ = rem(ns, 1_000_000_000)
    {seconds_, nanoseconds_}
  end
end
