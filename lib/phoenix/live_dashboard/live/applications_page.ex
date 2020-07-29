defmodule Phoenix.LiveDashboard.ApplicationsPage do
  use Phoenix.LiveDashboard.PageLive

  alias Phoenix.LiveDashboard.SystemInfo
  alias Phoenix.LiveDashboard.TableComponent

  @table_id :table

  @impl true
  def render(assigns) do
    ~L"""
      <%= live_component(assigns.socket, TableComponent, table_assigns(@page)) %>
    """
  end

  defp table_assigns(page) do
    %{
      columns: columns(),
      id: @table_id,
      page: page,
      row_attrs: &row_attrs/1,
      row_fetcher: &fetch_applications/2,
      title: "Applications"
    }
  end

  defp fetch_applications(params, node) do
    %{search: search, sort_by: sort_by, sort_dir: sort_dir, limit: limit} = params

    SystemInfo.fetch_applications(node, search, sort_by, sort_dir, limit)
  end

  defp columns() do
    [
      %{
        field: :name,
        header: "Name",
        header_attrs: [class: "pl-4"],
        cell_attrs: [class: "pl-4"],
        sortable: true
      },
      %{
        field: :description,
        header: "Description"
      },
      %{
        field: :state,
        header: "State",
        sortable: true
      },
      %{
        field: :tree?,
        header: "Sup tree?",
        cell_attrs: [class: "text-center"],
        format: &if(&1[:tree?], do: "✓")
      },
      %{
        field: :version,
        header: "Version",
        header_attrs: [class: "px-4"],
        cell_attrs: [class: "px-4"]
      }
    ]
  end

  defp row_attrs(application) do
    attrs = [id: "app-#{application[:name]}"]

    cond do
      application[:state] == :loaded ->
        [{:class, "text-muted"} | attrs]

      application[:tree?] ->
        [
          {"phx-click", "show_info"},
          {"phx-value-info", encode_app(application[:name])},
          {"phx-page-loading", true} | attrs
        ]

      true ->
        attrs
    end
  end
end
