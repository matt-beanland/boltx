# SPDX-FileCopyrightText: 2024 bolty contributors
# SPDX-License-Identifier: Apache-2.0

defimpl Enumerable, for: Bolty.Response do
  alias Bolty.Response

  def count(%Response{results: nil}), do: {:ok, 0}
  def count(%Response{results: []}), do: {:ok, 0}
  def count(%Response{results: results}), do: {:ok, length(results)}

  # No efficient membership check — return `{:error, __MODULE__}` so Enumerable
  # falls back to `reduce/3`. That makes `element in response` test row
  # membership, consistent with what iteration yields (the previous impl tested
  # `fields`, which disagreed with `reduce/3` iterating rows).
  def member?(%Response{}, _element), do: {:error, __MODULE__}

  # No efficient slicing — defer to the reduce-based fallback.
  def slice(%Response{}), do: {:error, __MODULE__}

  def reduce(%Response{results: nil}, acc, fun), do: reduce_list([], acc, fun)

  def reduce(%Response{results: results}, acc, fun) when is_list(results),
    do: reduce_list(results, acc, fun)

  defp reduce_list(_list, {:halt, acc}, _fun), do: {:halted, acc}
  defp reduce_list(list, {:suspend, acc}, fun), do: {:suspended, acc, &reduce_list(list, &1, fun)}
  defp reduce_list([], {:cont, acc}, _fun), do: {:done, acc}
  defp reduce_list([h | t], {:cont, acc}, fun), do: reduce_list(t, fun.(h, acc), fun)
end
