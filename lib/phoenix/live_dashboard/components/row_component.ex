defmodule Phoenix.LiveDashboard.RowComponent do
  use Phoenix.LiveDashboard.Web, :live_component

  @impl true
  def mount(socket) do
    {:ok, socket}
  end

  def normalize_params(params) do
    params
    |> validate_required([:components])
    |> normalize_components()
  end

  defp validate_required(params, list) do
    case Enum.find(list, &(not Map.has_key?(params, &1))) do
      nil -> :ok
      key -> raise ArgumentError, "expected #{inspect(key)} parameter to be received"
    end

    params
  end

  defp normalize_components(%{components: components} = params) when is_list(components) do
    components_length = length(components)

    if components_length > 0 and components_length < 4 do
      params
    else
      raise ArgumentError,
            "expected :components to have at min 1 compoment and max 3 components, received: #{
              inspect(components_length)
            }"
    end
  end

  defp normalize_components(%{components: components}) do
    raise ArgumentError, "expected :components to be a list, received: #{inspect(components)}"
  end

  @impl true
  def render(assigns) do
    ~L"""
    <div class="row">
      <%= for {component_module, component_params} <- @components do %>
        <%= live_component @socket, component_module, component_params %>
      <% end %>
    </div>
    """
  end
end
