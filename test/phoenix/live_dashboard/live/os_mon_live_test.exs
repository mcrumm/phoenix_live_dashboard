defmodule Phoenix.LiveDashboard.OSMonLiveTest do
  use ExUnit.Case, async: true

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  @endpoint Phoenix.LiveDashboardTest.Endpoint

  alias Phoenix.LiveDashboard.OSMonLive

  describe "OS mon page" do
    test "displays section titles" do
      {:ok, live, rendered} = live(build_conn(), "/dashboard/nonode@nohost/os")
      assert rendered =~ "Detailed CPU"
      assert rendered =~ "Total CPU"
      assert rendered =~ "Memory usage"
      assert rendered =~ "Disk usage"
    end
  end
end
