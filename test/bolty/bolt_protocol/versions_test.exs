# SPDX-FileCopyrightText: 2025 bolty contributors
# SPDX-License-Identifier: Apache-2.0

defmodule Bolty.BoltProtocol.VersionsTest do
  use ExUnit.Case, async: true

  alias Bolty.BoltProtocol.Versions

  describe "available_versions/0" do
    @tag core: true
    test "returns a list of {major, minor} versions" do
      assert Versions.available_versions() == [
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
    end
  end

  describe "latest versions" do
    @tag core: true
    test "latest_versions/1" do
      assert Versions.latest_versions() == [
               {6, 0},
               {5, 6..8},
               {5, 0..4},
               {0, 0}
             ]
    end
  end

  describe "parse/1" do
    @tag core: true
    test "parses the string form, not deprecated" do
      assert Versions.parse("5.4") == {{5, 4}, false}
      # A string distinguishes 5.10 from 5.1 (a float cannot).
      assert Versions.parse("5.10") == {{5, 10}, false}
    end

    @tag core: true
    test "accepts an explicit {major, minor} / {major, range} tuple, not deprecated" do
      assert Versions.parse({5, 4}) == {{5, 4}, false}
      assert Versions.parse({5, 0..4}) == {{5, 0..4}, false}
    end

    @tag core: true
    test "accepts a float or bare integer but flags it deprecated" do
      assert Versions.parse(5.4) == {{5, 4}, true}
      assert Versions.parse(5) == {{5, 0}, true}
    end
  end

  describe "format/1" do
    @tag core: true
    test "renders a {major, minor} version as a string" do
      assert Versions.format({5, 8}) == "5.8"
      assert Versions.format({5, 10}) == "5.10"
    end
  end

  describe "to_bytes/1" do
    @tag core: true
    test "converts a {major, minor} version to bytes" do
      assert Versions.to_bytes({5, 3}) == <<0, 0, 3, 5>>
      assert Versions.to_bytes({4, 3}) == <<0, 0, 3, 4>>
    end

    @tag core: true
    test "converts a {major, range} version to bytes" do
      assert Versions.to_bytes({5, 0..4}) == <<0, 4, 4, 5>>
      assert Versions.to_bytes({4, 1..3}) == <<0, 2, 3, 4>>
    end
  end
end
