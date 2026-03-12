defmodule Bolty.Test.Support.Database do
  def clear(conn) do
    Bolty.query!(conn, "MATCH (n) DETACH DELETE n")
  end
end
