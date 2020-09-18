defmodule TeslaPowerwall.Meter do
  @type meter_type :: :load | :site | :solar | :battery

  @default_precision 3

  @spec is_sending_to(any, meter_type()) :: boolean()
  def is_sending_to(meter, meter_type, precision \\ @default_precision) do
    case get_instant_power(meter) do
      {:ok, instant_power} ->
        instant_power_kwh = convert_to_kwh(instant_power, precision)

        if meter_type == :load do
          # For meter 'load' instant power is always positive
          {:ok, instant_power_kwh > 0}
        else
          {:ok, instant_power_kwh < 0}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec is_drawing_from(any, meter_type()) :: {:ok, boolean()}
  def is_drawing_from(meter, meter_type, precision \\ @default_precision) do
    if meter_type == :load do
      {:ok, false}
    else
      case get_instant_power(meter) do
        {:ok, instant_power} -> {:ok, convert_to_kwh(instant_power, precision) > 0}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @spec is_active(any) :: boolean()
  def is_active(meter) do
    with {:ok, instant_power} <- get_instant_power(meter) do
      {:ok, convert_to_kwh(instant_power) != 0}
    end
  end

  @spec get_power(any) :: boolean()
  def get_power(meter, precision \\ 3) do
    case get_instant_power(meter) do
      {:ok, instant_power} -> {:ok, convert_to_kwh(instant_power)}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec convert_to_kwh(number, number) :: float
  def convert_to_kwh(power, precision \\ 3)

  def convert_to_kwh(power, precision) when precision == -1 do
    power / 1000
  end

  def convert_to_kwh(power, precision) do
    Float.round(power / 1000, precision)
  end

  defp get_instant_power(meter) do
    case Map.fetch(meter, "instant_power") do
      {:ok, instant_power} -> {:ok, instant_power}
      :error -> {:error, {:missing_key, :instant_power}}
    end
  end
end
