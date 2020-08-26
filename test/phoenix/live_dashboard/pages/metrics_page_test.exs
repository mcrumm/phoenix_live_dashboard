defmodule Phoenix.LiveDashboard.MetricsPageTest do
  use ExUnit.Case, async: true

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  @endpoint Phoenix.LiveDashboardTest.Endpoint

  test "menu_link/2" do
    assert :skip = Phoenix.LiveDashboard.MetricsPage.menu_link(%{}, %{running_dashboard?: false})

    link = "https://hexdocs.pm/phoenix_live_dashboard/metrics.html"

    assert {:disabled, "Metrics", ^link} =
             Phoenix.LiveDashboard.MetricsPage.menu_link(
               %{"metrics" => nil},
               %{running_dashboard?: true}
             )

    assert {:ok, "Metrics"} =
             Phoenix.LiveDashboard.MetricsPage.menu_link(
               %{"metrics" => {Module, :fun}},
               %{running_dashboard?: true}
             )
  end

  test "redirects to the first metrics group if no metric group is provided" do
    {:error, {:live_redirect, %{to: "/dashboard/nonode%40nohost/metrics?group=ecto"}}} =
      live(build_conn(), "/dashboard/nonode@nohost/metrics")
  end

  test "shows given group metrics" do
    {:ok, live, _} = live(build_conn(), "/dashboard/nonode@nohost/metrics?group=phx")
    rendered = render(live)
    assert rendered =~ "Updates automatically"
    assert rendered =~ "Phx"
    assert rendered =~ "Ecto"
    assert rendered =~ "MyApp"
    assert rendered =~ ~s|data-title="phx.b.c"|
    assert rendered =~ ~s|data-title="phx.b.d"|

    send(live.pid, {:telemetry, [{0, nil, "value", System.system_time(:millisecond)}]})

    # Guarantees the message above has been processed
    _ = render(live)

    # Guarantees the components have been updated
    assert render(live) =~ ~s|<span data-x="C" data-y="value"|
  end

  test "redirects on unknown group" do
    {:error, {:live_redirect, %{to: "/dashboard/nonode%40nohost/metrics"}}} =
      live(build_conn(), "/dashboard/nonode@nohost/metrics?group=unknown")
  end

  test "renders history for metrics" do
    {:ok, live, _} = live(build_conn(), "/dashboard/nonode@nohost/metrics?group=phx")

    # Guarantees the components have been updated
    assert render(live) =~
             ~s|<span data-x="#{TestHistory.label()}" data-y="#{TestHistory.measurement()}"|
  end
end
