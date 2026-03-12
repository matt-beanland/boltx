if Code.ensure_loaded?(Jason) do
  defmodule Bolty.ResponseEncoder.Json.Jason do
    @moduledoc """
    A default implementation for Jason encoding library.

    More info about Jason: [https://hex.pm/packages/jason](https://hex.pm/packages/jason)

    Allow this usage:
    ```
    conn = Bolty.conn()
    {:ok, res} = Bolty.query(conn, "MATCH (t:TestNode) RETURN t")
    Jason.encode!(res)
    ```

    Default implementation can be overriden by providing your own implementation.

    More info about implementation: [https://hexdocs.pm/jason/readme.html#differences-to-poison](https://hexdocs.pm/jason/readme.html#differences-to-poison)

    #### Note:
    In order to benefit from Bolty.ResponseEncoder implementation, use
    `Bolty.ResponseEncoder.Json.encode` and pass the result to the Jason
    encoding functions.
    """
    alias Bolty.Types
    alias Bolty.ResponseEncoder.Json

    defimpl Jason.Encoder, for: [Types.Node, Types.Relationship, Types.Path, Types.Point] do
      @spec encode(struct(), Jason.Encode.opts()) :: iodata()
      def encode(data, opts) do
        data
        |> Json.encode()
        |> Jason.Encode.map(opts)
      end
    end

    defimpl Jason.Encoder,
      for: [Types.DateTimeWithTZOffset, Types.TimeWithTZOffset, Duration] do
      @spec encode(struct(), Jason.Encode.opts()) :: iodata()
      def encode(data, opts) do
        data
        |> Json.encode()
        |> Jason.Encode.string(opts)
      end
    end
  end
end
