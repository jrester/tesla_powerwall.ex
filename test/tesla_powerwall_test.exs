defmodule TeslaPowerwallTest do
  use ExUnit.Case
  doctest TeslaPowerwall

  test "create Powerwall struct with ip" do
    assert TeslaPowerwall.new("192.0.2.100").endpoint == "https://192.0.2.100/"
  end

  test "create Powerwall struct with domain" do
    assert TeslaPowerwall.new("powerwall.local").endpoint == "https://powerwall.local/"
  end

  test "new transforms scheme to https" do
    assert TeslaPowerwall.new("http://192.0.2.100").endpoint == "https://192.0.2.100/"
  end
end
