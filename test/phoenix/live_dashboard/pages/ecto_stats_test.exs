defmodule Phoenix.LiveDashboard.EctoStatsPageTest do
  use ExUnit.Case, async: true

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  @endpoint Phoenix.LiveDashboardTest.Endpoint

  alias Phoenix.LiveDashboard.EctoStatsPage
  alias Phoenix.LiveDashboardTest.Repo
  alias Phoenix.LiveDashboardTest.SecondaryRepo

  test "menu_link/2" do
    assert :skip = EctoStatsPage.menu_link(%{repos: []}, %{})
    assert :skip = EctoStatsPage.menu_link(%{repos: [Repo]}, %{processes: []})

    assert {:ok, "Ecto Stats"} = EctoStatsPage.menu_link(%{repos: [Repo]}, %{processes: [Repo]})

    assert {:ok, "Ecto Stats"} =
             EctoStatsPage.menu_link(%{repos: :auto_discover}, %{processes: []})
  end

  test "renders" do
    start_main_repo!()

    {:ok, live, _} = live(build_conn(), ecto_stats_path())
    rendered = render(live)

    assert rendered =~ "Phoenix.LiveDashboardTest.Repo"
    refute rendered =~ "Phoenix.LiveDashboardTest.SecondaryRepo"

    assert rendered =~ "All locks"
    assert rendered =~ "Extensions"
    assert rendered =~ "Transactionid"
    assert rendered =~ "Granted"

    start_secondary_repo!()

    {:ok, live, _} = live(build_conn(), ecto_stats_path())
    rendered = render(live)

    assert rendered =~ "Phoenix.LiveDashboardTest.Repo"
    assert rendered =~ "Phoenix.LiveDashboardTest.SecondaryRepo"
  end

  test "renders error without running repos" do
    {:ok, live, _} = live(build_conn(), ecto_stats_path())
    rendered = render(live)

    refute rendered =~ "Phoenix.LiveDashboardTest.Repo"

    assert rendered =~
             "No Ecto repository was found. Currently only PSQL databases are supported."
  end

  @forbidden_navs [:kill_all, :mandelbrot]

  test "navs" do
    start_main_repo!()

    for {nav, _} <- EctoPSQLExtras.queries(Repo), nav not in @forbidden_navs do
      assert {:ok, _, _} = live(build_conn(), ecto_stats_path(nav))
    end

    start_secondary_repo!()

    available_navs =
      for {nav, _} <- EctoPSQLExtras.queries(SecondaryRepo), nav not in @forbidden_navs, do: nav

    nav = Enum.random(available_navs)

    assert {:ok, live, _} = live(build_conn(), ecto_stats_path(nav, "", SecondaryRepo))

    assert live
           |> element("a.active", "Phoenix.LiveDashboardTest.SecondaryRepo")
           |> has_element?()

    another_nav = Enum.random(available_navs -- [nav])

    live
    |> element(~s|a.nav-link[href*='nav=#{another_nav}']|)
    |> render_click()

    # Keep the same repo selected
    assert live
           |> element("a.active", "Phoenix.LiveDashboardTest.SecondaryRepo")
           |> has_element?()
  end

  test "search" do
    start_main_repo!()

    {:ok, live, _} = live(build_conn(), ecto_stats_path(:extensions))
    rendered = render(live)
    assert rendered =~ "Default version"
    assert rendered =~ "Installed version"
    assert rendered =~ "fuzzystrmatch"
    assert rendered =~ "hstore"

    {:ok, live, _} = live(build_conn(), ecto_stats_path(:extensions, "hstore"))
    rendered = render(live)
    assert rendered =~ "Default version"
    assert rendered =~ "Installed version"
    refute rendered =~ "fuzzystrmatch"
    assert rendered =~ "hstore"
  end

  defp ecto_stats_path() do
    "/dashboard/ecto_stats"
  end

  defp ecto_stats_path(nav) do
    "#{ecto_stats_path()}?nav=#{nav}"
  end

  defp ecto_stats_path(nav, search) do
    "#{ecto_stats_path()}?nav=#{nav}&search=#{search}"
  end

  defp ecto_stats_path(nav, search, repo) do
    "#{ecto_stats_path()}?nav=#{nav}&search=#{search}&repo=#{repo}"
  end

  defp start_main_repo! do
    start_supervised!(Repo)
  end

  defp start_secondary_repo! do
    start_supervised!(SecondaryRepo)
  end
end
