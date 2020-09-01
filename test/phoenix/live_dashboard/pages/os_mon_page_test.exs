defmodule Phoenix.LiveDashboard.OSMonPageTest do
  use ExUnit.Case, async: true

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  @endpoint Phoenix.LiveDashboardTest.Endpoint

  test "menu_link/2" do
    link = "https://hexdocs.pm/phoenix_live_dashboard/os_mon.html"

    capabilities = %{applications: %{os_mon: false}}

    assert {:disabled, "OS Data", ^link} =
             Phoenix.LiveDashboard.OSMonPage.menu_link(%{}, capabilities)

    capabilities = %{applications: %{os_mon: true}}
    assert {:ok, "OS Data"} = Phoenix.LiveDashboard.OSMonPage.menu_link(%{}, capabilities)
  end

  describe "OS mon page" do
    test "displays section titles" do
      {:ok, _live, rendered} = live(build_conn(), "/dashboard/nonode@nohost/os_mon")
      assert rendered =~ "CPU"
      assert rendered =~ "Memory"
      assert rendered =~ "Disk"
    end
  end
end
