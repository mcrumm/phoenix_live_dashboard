defmodule Phoenix.LiveDashboard.PortsLive do
  use Phoenix.LiveDashboard.Web, :live_view
  import Phoenix.LiveDashboard.LiveHelpers

  alias Phoenix.LiveDashboard.SystemInfo
  alias Phoenix.LiveDashboard.TableComponent

  @page :ports
  @table_id :table

  @impl true
  def mount(%{"node" => _} = params, session, socket) do
    {:ok, assign_mount(socket, @page, params, session, true)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, socket |> assign_params(params) |> assign(:params, params)}
  end

  @impl true
  def render(assigns) do
    ~L"""
      <%= live_component(assigns.socket, TableComponent, table_assigns(@params, @menu.node)) %>
    """
  end

  defp table_assigns(params, node) do
    %{
      columns: columns(),
      id: @table_id,
      rows_name: "ports",
      params: params,
      row_attrs: &row_attrs/1,
      row_fetcher: &fetch_ports(&1, node),
      self_path: &self_path(&1, node, &2),
      title: "Ports"
    }
  end

  defp fetch_ports(params, node) do
    %{search: search, sort_by: sort_by, sort_dir: sort_dir, limit: limit} = params

    SystemInfo.fetch_ports(node, search, sort_by, sort_dir, limit)
  end

  defp columns() do
    [
      %{
        field: :port,
        header_attrs: [class: "pl-4"],
        cell_attrs: [class: "tabular-column-id pl-4"],
        format: &(&1[:port] |> encode_port() |> String.replace_prefix("Port", ""))
      },
      %{
        field: :name,
        header: "Name or path",
        cell_attrs: [class: "w-50"],
        format: &format_path(&1[:name])
      },
      %{
        field: :os_pid,
        header: "OS pid",
        format: &if(&1[:os_pid] != :undefined, do: &1[:os_pid])
      },
      %{
        field: :input,
        header_attrs: [class: "text-right"],
        cell_attrs: [class: "tabular-column-bytes"],
        format: &format_bytes(&1[:input]),
        sortable: true
      },
      %{
        field: :output,
        header_attrs: [class: "text-right pr-4"],
        cell_attrs: [class: "tabular-column-bytes pr-4"],
        format: &format_bytes(&1[:output]),
        sortable: true
      },
      %{
        field: :id,
        header_attrs: [class: "text-right"],
        cell_attrs: [class: "text-right"]
      },
      %{
        field: :owner,
        format: &inspect(&1[:connected])
      }
    ]
  end

  defp row_attrs(port) do
    [
      {"phx-click", "show_info"},
      {"phx-value-port", encode_port(port[:port])},
      {"phx-page-loading", true}
    ]
  end

  @impl true
  def handle_info({:node_redirect, node}, socket) do
    {:noreply, push_redirect(socket, to: self_path(socket, node, socket.assigns.params))}
  end

  def handle_info(:refresh, socket) do
    %{params: params, menu: menu} = socket.assigns
    send_update(TableComponent, table_assigns(params, menu.node))
    {:noreply, socket}
  end

  @impl true
  def handle_event("show_info", %{"port" => port}, socket) do
    params = Map.put(socket.assigns.params, :info, port)
    {:noreply, push_patch(socket, to: self_path(socket, node(), params))}
  end

  defp self_path(socket, node, params) do
    live_dashboard_path(socket, :ports, node, params)
  end
end
