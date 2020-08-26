defmodule Phoenix.LiveDashboard.Router do
  @moduledoc """
  Provides LiveView routing for LiveDashboard.
  """

  @doc """
  Defines a LiveDashboard route.

  It expects the `path` the dashboard will be mounted at
  and a set of options.

  ## Options

    * `:metrics` - Configures the module to retrieve metrics from.
      It can be a `module` or a `{module, function}`. If nothing is
      given, the metrics functionality will be disabled.

    * `:env_keys` - Configures environment variables to display.
      It is defined as a list of string keys. If not set, the environment
      information will not be displayed.

    * `:live_socket_path` - Configures the socket path. it must match
      the `socket "/live", Phoenix.LiveView.Socket` in your endpoint.

    * `:metrics_history` - Configures a callback for retreiving metric history.
      It must be an "MFA" tuple of  `{Module, :function, arguments}` such as
        metrics_history: {MyStorage, :metrics_history, []}
      If not set, metrics will start out empty/blank and only display
      data that occurs while the browser page is open.

  ## Examples

      defmodule MyAppWeb.Router do
        use Phoenix.Router
        import Phoenix.LiveDashboard.Router

        scope "/", MyAppWeb do
          pipe_through [:browser]
          live_dashboard "/dashboard",
            metrics: {MyAppWeb.Telemetry, :metrics},
            env_keys: ["APP_USER", "VERSION"],
            metrics_history: {MyStorage, :metrics_history, []}
        end
      end

  """
  defmacro live_dashboard(path, opts \\ []) do
    quote bind_quoted: binding() do
      scope path, alias: false, as: false do
        import Phoenix.LiveView.Router, only: [live: 4]

        opts = Phoenix.LiveDashboard.Router.__options__(opts)
        live "/", Phoenix.LiveDashboard.PageLive, :home, opts ++ [page: "home", node: node()]

        # Catch-all for URL generation
        live "/:node/:page", Phoenix.LiveDashboard.PageLive, :page, opts
      end
    end
  end

  @doc false
  def __options__(options) do
    live_socket_path = Keyword.get(options, :live_socket_path, "/live")

    metrics =
      case options[:metrics] do
        nil ->
          nil

        mod when is_atom(mod) ->
          {mod, :metrics}

        {mod, fun} when is_atom(mod) and is_atom(fun) ->
          {mod, fun}

        other ->
          raise ArgumentError,
                ":metrics must be a tuple with {Mod, fun}, " <>
                  "such as {MyAppWeb.Telemetry, :metrics}, got: #{inspect(other)}"
      end

    env_keys =
      case options[:env_keys] do
        nil ->
          nil

        keys when is_list(keys) ->
          keys

        other ->
          raise ArgumentError,
                ":env_keys must be a list of strings, got: " <> inspect(other)
      end

    metrics_history =
      case options[:metrics_history] do
        nil ->
          nil

        {module, function, args}
        when is_atom(module) and is_atom(function) and is_list(args) ->
          {module, function, args}

        other ->
          raise ArgumentError,
                ":metrics_history must be a tuple of {module, function, args}, got: " <>
                  inspect(other)
      end

    additional_pages =
      case options[:additional_pages] do
        nil ->
          []

        pages when is_list(pages) ->
          normalize_additional_pages(pages)

        other ->
          raise ArgumentError, ":additional_pages must be a keyword, got: " <> inspect(other)
      end

    [
      session: {__MODULE__, :__session__, [metrics, env_keys, metrics_history, additional_pages]},
      private: %{live_socket_path: live_socket_path},
      layout: {Phoenix.LiveDashboard.LayoutView, :dash},
      as: :live_dashboard
    ]
  end

  defp normalize_additional_pages(pages) do
    Enum.map(pages, fn
      module when is_atom(module) ->
        {module, []}

      {module, args} when is_atom(module) and is_list(args) ->
        {module, args}

      other ->
        raise ArgumentError,
              "invalid :additional_page, must be a tuple {module, args}, got: " <> inspect(other)
    end)
  end

  @doc false
  def __session__(conn, metrics, env_keys, metrics_history, additional_pages) do
    metrics_session = %{
      "metrics" => metrics,
      "metrics_history" => metrics_history
    }

    request_logger_session = %{
      "request_logger" => Phoenix.LiveDashboard.RequestLogger.param_key(conn)
    }

    pages =
      [
        {"home", {Phoenix.LiveDashboard.HomePage, %{"env_keys" => env_keys}}},
        {"os_mon", {Phoenix.LiveDashboard.OSMonPage, %{}}},
        {"metrics", {Phoenix.LiveDashboard.MetricsPage, metrics_session}},
        {"request_logger", {Phoenix.LiveDashboard.RequestLoggerPage, request_logger_session}},
        {"applications", {Phoenix.LiveDashboard.ApplicationsPage, %{}}},
        {"processes", {Phoenix.LiveDashboard.ProcessesPage, %{}}},
        {"ports", {Phoenix.LiveDashboard.PortsPage, %{}}},
        {"sockets", {Phoenix.LiveDashboard.SocketsPage, %{}}},
        {"ets", {Phoenix.LiveDashboard.EtsPage, %{}}}
      ]
      |> Enum.concat(additional_pages)
      |> Enum.map(fn {key, {module, opts}} -> {key, {module, module.init(opts)}} end)

    %{
      "pages" => pages
    }
  end
end
