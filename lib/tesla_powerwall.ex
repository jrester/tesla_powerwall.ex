defmodule TeslaPowerwall do
  alias TeslaPowerwall.Powerwall

  require Logger

  @type device_type :: :GW1 | :GW2 | :SWC
  @type grid_status_type :: :connected | :islanded_ready | :islanded | :transition_to_grid

  @type powerwall_error ::
          :missing_key
          | :powerwall_version_required
          | powerwall_parse_error()
          | powerwall_api_error()
  @type powerwall_parse_error :: :unknown_device_type | :invalid_grid_status
  @type powerwall_api_error :: :error_page_not_found

  @default_finch_name TeslaPowerwallFinch

  @doc ~S"""
  Starts finch based on the configuration of `powerwall`.

  Most powerwalls serve a self signed certificate. As such a normal request will fail because of the 'invalid' certificate.
  To circumvent this the finch client must be instructed to not verify the certificate.
  This can be achieved by passing `[transport_opts: [verify: :verify_none]]` to the `conn_opts` when configuring the Finch pool:

  **Example**
  ```
    Finch.start_link(
      name: TeslaPowerwallFinch,
      pools: %{
        "192.0.2.100" => [size: 5, conn_opts: [transport_opts: [verify: :verify_none]]]
      }
    )
  ```
  When using a different name than `TeslaPowerwallFinch` it must be passed to the `Powerwall` struct either when calling `TeslaPowerwall.new\2` or by manually setting `finch_name` of your powerwall struct.
  """
  def start_finch(powerwall) do
    Finch.start_link(
      name: powerwall.finch_name,
      pools: %{
        powerwall.endpoint => [size: 5, conn_opts: [transport_opts: [verify: :verify_none]]]
      }
    )
  end

  @spec new(String.t(), any) :: Powerwall
  def new(endpoint, finch_name \\ @default_finch_name) do
    uri =
      case URI.parse(endpoint) do
        %URI{host: nil} -> %URI{host: endpoint}
        uri -> uri
      end

    %Powerwall{
      endpoint:
        uri
        |> Map.put(:scheme, "https")
        # Otherwise port may be 80 if the scheme was upgraded from http
        |> Map.put(:port, 443)
        |> Map.put(:path, "/")
        |> URI.to_string(),
      finch_name: finch_name
    }
  end

  @spec get(Powerwall, String.t()) :: any
  def get(powerwall, path) do
    Finch.build(:get, URI.merge(powerwall.endpoint, Path.join("/api", path)))
    |> Finch.request(powerwall.finch_name)
    |> handle_response()
  end

  @spec get_charge(Powerwall) :: {:ok, float} | {:error, any}
  def get_charge(powerwall) do
    case get(powerwall, "system_status/soe") do
      {:ok, val} -> {:ok, Map.get(val, "percentage")}
      err -> err
    end
  end

  @spec get_meters(Powerwall) :: any | {:error}
  def get_meters(powerwall) do
    case get(powerwall, "meters/aggregates") do
      {:ok, meters} -> parse_meters(meters)
      other -> other
    end
  end

  def get_device_type(%{version: version}) when is_nil(version) do
    {:error, :powerwall_version_required}
  end

  def get_device_type(powerwall) do
    if Version.match?(powerwall.version, "< 1.46.0") do
      get(powerwall, "device_type")
    else
      powerwall
    end
  end

  def get_status(powerwall) do
    case get(powerwall, "status") do
      {:ok, status} -> parse_status(status)
      {:error, reason} -> {:error, reason}
    end
  end

  def get_status_and_update(powerwall) do
    with {:ok, status} <- get_status(powerwall),
         {:ok, version} <- Map.fetch(status, "version") do
      {:ok, {%{powerwall | version: version}, status}}
    else
      :error -> {:error, {:missing_key, :version}}
      {:error, reason} -> {:error, reason}
    end
  end

  def get_version(powerwall) do
    case get_status(powerwall) do
      {:ok, status} -> Map.fetch(status, "version")
      {:error, reason} -> {:error, reason}
    end
  end

  def get_version_and_update(powerwall) do
    case get_status_and_update(powerwall) do
      {:ok, {powerwall, status}} -> {:ok, {powerwall, Map.get(status, "version")}}
      {:error, reason} -> {:error, reason}
    end
  end

  def get_sitemaster(powerwall) do
    get(powerwall, "sitemaster")
  end

  @spec get_grid_status(Powerwall) :: {:ok, grid_status_type} | {:error, any}
  def get_grid_status(powerwall) do
    with {:ok, resp} <- get(powerwall, "system_status/grid_status"),
         {:ok, grid_status} <- Map.fetch(resp, "grid_status"),
         {:ok, grid_status_parsed} <- parse_grid_status(grid_status) do
      {:ok, grid_status_parsed}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def get_site_info(powerwall) do
    get(powerwall, "site_info")
  end

  def get_powerwalls(powerwall) do
    get(powerwall, "powerwalls")
  end

  def get_serial_numbers(powerwall) do
    with {:ok, resp} <- get_powerwalls(powerwall),
         {:ok, powerwalls} <- Map.fetch(resp, "powerwalls") do
      Enum.map(powerwalls, fn p -> Map.get(p, "PackageSerialNumber") end)
    else
      {:error, reason} -> {:error, reason}
    end
  end

  ### Private

  defp handle_response(resp) do
    case resp do
      {:ok, %Finch.Response{body: body, status: 200}} ->
        case Jason.decode(body) do
          {:ok, decoded_body} -> {:ok, decoded_body}
          {:error, reason} -> {:error, reason}
        end

      {:ok, %Finch.Response{status: 404}} ->
        {:error, :error_page_not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_meters(meters) do
    Enum.map(meters, fn {meter, vals} ->
      case meter do
        "solar" -> {:solar, vals}
        "load" -> {:load, vals}
        "site" -> {:site, vals}
        "battery" -> {:battery, vals}
      end
    end)
  end

  @spec parse_grid_status(any) :: {:ok, grid_status_type} | :error
  defp parse_grid_status(status) do
    case status do
      "SystemGridConnected" -> {:ok, :connected}
      "SystemIslandedReady" -> {:ok, :islanded_ready}
      "SystemIslandedActive" -> {:ok, :islanded}
      "SystemTransitionToGrid" -> {:ok, :transition_to_grid}
      _ -> {:error, {:invalid_grid_status, status}}
    end
  end

  defp parse_status(status) do
    case device_type_or_nil(status) do
      {:ok, device_type} -> {:ok, Map.put(status, "device_type", device_type)}
      {:error, reason} -> {:error, reason}
      nil -> status
    end
  end

  @spec parse_device_type(String.t()) ::
          {:ok, device_type()} | {:error, {:unknown_device_type, String.t()}}
  defp parse_device_type(device_type) do
    case device_type do
      "hec" -> {:ok, :GW1}
      "teg" -> {:ok, :GW2}
      "smc" -> {:ok, :SMC}
      unknown -> {:error, {:unknown_device_type, unknown}}
    end
  end

  defp device_type_or_nil(resp) do
    case Map.fetch(resp, "device_type") do
      {:ok, device_type} -> parse_device_type(device_type)
      :error -> nil
    end
  end
end
