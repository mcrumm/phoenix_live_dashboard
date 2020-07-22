defmodule Phoenix.LiveDashboard.SocketsPage do
  use Phoenix.LiveDashboard.PageLive

  alias Phoenix.LiveDashboard.SystemInfo
  alias Phoenix.LiveDashboard.TableComponent

  @table_id :table

  @impl true
  def render(assigns) do
    ~L"""
      <%= live_component(assigns.socket, TableComponent, table_assigns(@menu)) %>
    """
  end

  defp table_assigns(menu) do
    %{
      columns: columns(),
      id: @table_id,
      menu: menu,
      row_attrs: &row_attrs/1,
      row_fetcher: &fetch_sockets/2,
      title: "Sockets"
    }
  end

  defp fetch_sockets(params, node) do
    %{search: search, sort_by: sort_by, sort_dir: sort_dir, limit: limit} = params

    SystemInfo.fetch_sockets(node, search, sort_by, sort_dir, limit)
  end

  defp columns() do
    [
      %{
        field: :port,
        header_attrs: [class: "pl-4"],
        format: &(&1[:port] |> encode_socket() |> String.trim_leading("Socket")),
        cell_attrs: [class: "tabular-column-name tabular-column-id pl-4"]
      },
      %{
        field: :module,
        sortable: true
      },
      %{
        field: :send_oct,
        header: "Sent",
        header_attrs: [class: "text-right pr-4"],
        format: &format_bytes(&1[:send_oct]),
        cell_attrs: [class: "tabular-column-bytes pr-4"],
        sortable: true
      },
      %{
        field: :recv_oct,
        header: "Received",
        header_attrs: [class: "text-right pr-4"],
        format: &format_bytes(&1[:recv_oct]),
        cell_attrs: [class: "tabular-column-bytes pr-4"],
        sortable: true
      },
      %{
        field: :local_address,
        header: "Local Address",
        sortable: true
      },
      %{
        field: :foreign_address,
        sortable: true
      },
      %{
        field: :state,
        sortable: true
      },
      %{
        field: :type,
        sortable: true
      },
      %{
        field: :connected,
        header: "Owner",
        format: &encode_pid(&1[:connected])
      }
    ]
  end

  defp row_attrs(socket) do
    [
      {"phx-click", "show_info"},
      {"phx-value-info", encode_socket(socket[:port])},
      {"phx-page-loading", true}
    ]
  end
end
