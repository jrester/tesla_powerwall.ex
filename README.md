# TeslaPowerwall

Elixir API for the Tesla Powerwall.

> Note: This is not an official API provided by Tesla and therefore might be incomplete and fail at any time.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `tesla_powerwall` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:tesla_powerwall, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/tesla_powerwall](https://hexdocs.pm/tesla_powerwall).


### API

```elixir
powerwall = TeslaPowerwall.new("<ip address>")

TeslaPowerwall.get_charge(powerwall)
#=> {:ok, 100}
```

#### Meters

```elixir
TeslaPowerwall.get_meters(powerwall)
|> Keyword.get(:battery)
|> TeslaPowerwall.Meter.is_active()
#=> {:ok, true}
```

### Finch

Most powerwalls serve a self signed certificate. As such a normal request will fail because of the 'invalid' certificate.
To circumvent this the finch client must be instructed to not verify the certificate.
This can be achieved by passing `[transport_opts: [verify: :verify_none]]` to the `conn_opts` when configuring the Finch pool:

```elixir
Finch.start_link(
  name: TeslaPowerwallFinch,
  pools: %{
    "192.0.2.100" => [size: 5, conn_opts: [transport_opts: [verify: :verify_none]]]
  }
)
```

When using a different name than `TeslaPowerwallFinch` it must be passed to the `Powerwall` struct either when calling `TeslaPowerwall.new\2` or by manually setting `finch_name` of your powerwall struct.