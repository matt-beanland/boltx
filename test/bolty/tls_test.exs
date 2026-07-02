# SPDX-FileCopyrightText: 2024 bolty contributors
# SPDX-License-Identifier: Apache-2.0

defmodule Bolty.TLSTest do
  @moduledoc """
  End-to-end TLS verification tests against the TLS-enabled `neo4j-bolt5`
  compose service (port 7687), whose server certificate is signed by the
  throwaway CA in test/tls/certs/ca.crt.

  Excluded by default. To run:

      ./test/tls/gen_certs.sh
      docker compose up -d --build neo4j-bolt5
      mix test --include tls test/bolty/tls_test.exs
  """
  use ExUnit.Case, async: false

  @moduletag :tls

  alias Bolty.Client

  @host "localhost"
  @port 7687
  @ca_path Path.join([__DIR__, "..", "tls", "certs", "ca.crt"]) |> Path.expand()

  defp base_opts do
    [
      hostname: @host,
      port: @port,
      auth: [username: "neo4j", password: "password"],
      user_agent: "boltyTest/1"
    ]
  end

  describe "bolt+s (full verification)" do
    test "connects when the signing CA is trusted via ssl_opts" do
      opts = [scheme: "bolt+s", ssl_opts: [cacertfile: @ca_path]] ++ base_opts()

      assert {:ok, client} = Client.connect(opts)
      assert is_float(client.bolt_version)
    end

    test "fails against the OS trust store (server CA is unknown)" do
      # No cacertfile override, so the strict defaults verify against the system
      # trust store, which does not contain our throwaway CA. This proves +s
      # actually enforces verification rather than silently accepting any cert.
      opts = [scheme: "bolt+s"] ++ base_opts()

      assert {:error, _reason} = Client.connect(opts)
    end

    test "fails when the presented hostname does not match the certificate" do
      # Cert SANs are localhost / 127.0.0.1; connect by an unmatched name.
      opts =
        [scheme: "bolt+s", hostname: "not-in-cert.example", ssl_opts: [cacertfile: @ca_path]] ++
          Keyword.delete(base_opts(), :hostname)

      assert {:error, _reason} = Client.connect(opts)
    end
  end

  describe "bolt+ssc (self-signed / trust-all)" do
    test "connects without trusting the CA (verify_none)" do
      opts = [scheme: "bolt+ssc"] ++ base_opts()

      assert {:ok, client} = Client.connect(opts)
      assert is_float(client.bolt_version)
    end
  end
end
