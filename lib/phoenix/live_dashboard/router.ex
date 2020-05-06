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

  ## Examples

      defmodule MyAppWeb.Router do
        use Phoenix.Router
        import Phoenix.LiveDashboard.Router

        scope "/", MyAppWeb do
          pipe_through [:browser]
          live_dashboard "/dashboard",
            metrics: {MyAppWeb.Telemetry, :metrics},
            env_keys: ["APP_USER", "VERSION"]
        end
      end

  """
  defmacro live_dashboard(path, opts \\ []) do
    quote bind_quoted: binding() do
      scope path, alias: false, as: false do
        import Phoenix.LiveView.Router, only: [live: 4]

        plugins = Phoenix.LiveDashboard.Router.__plugins__(opts)
        opts = Phoenix.LiveDashboard.Router.__options__(opts, plugins)
        live "/", Phoenix.LiveDashboard.HomeLive, :home, opts
        live "/:node", Phoenix.LiveDashboard.HomeLive, :home, opts
        live "/:node/os", Phoenix.LiveDashboard.OSMonLive, :os_mon, opts
        live "/:node/metrics", Phoenix.LiveDashboard.MetricsLive, :metrics, opts
        live "/:node/metrics/:group", Phoenix.LiveDashboard.MetricsLive, :metrics, opts
        live "/:node/ports", Phoenix.LiveDashboard.PortsLive, :ports, opts
        live "/:node/ports/:port", Phoenix.LiveDashboard.PortsLive, :ports, opts
        live "/:node/processes", Phoenix.LiveDashboard.ProcessesLive, :processes, opts
        live "/:node/processes/:pid", Phoenix.LiveDashboard.ProcessesLive, :processes, opts
        live "/:node/ets", Phoenix.LiveDashboard.EtsLive, :ets, opts
        live "/:node/ets/:ref", Phoenix.LiveDashboard.EtsLive, :ets, opts
        live "/:node/sockets", Phoenix.LiveDashboard.SocketsLive, :sockets, opts
        live "/:node/sockets/:port", Phoenix.LiveDashboard.SocketsLive, :sockets, opts
        live "/:node/applications", Phoenix.LiveDashboard.ApplicationsLive, :applications, opts

        live "/:node/request_logger",
             Phoenix.LiveDashboard.RequestLoggerLive,
             :request_logger,
             opts

        live "/:node/request_logger/:stream",
             Phoenix.LiveDashboard.RequestLoggerLive,
             :request_logger,
             opts

        for {path, module, id} <- Phoenix.LiveDashboard.Plugins.call(plugins, :add_route, []) do
          live "#{path}", module, id, opts
        end
      end
    end
  end

  @doc false
  def __options__(options, plugins) do
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
        nil -> nil
        keys when is_list(keys) -> keys
        other -> raise ArgumentError,
              ":env_keys must be a list of strings, got: #{inspect(other)}"
      end
    [
      session: {__MODULE__, :__session__, [metrics, env_keys, plugins]},
      layout: {Phoenix.LiveDashboard.LayoutView, :dash},
      as: :live_dashboard
    ]
  end

  @doc false
  def __session__(conn, metrics, env_keys, plugins) do
    %{
      "metrics" => metrics,
      "env_keys" => env_keys,
      "plugins" => plugins,
      "request_logger" => Phoenix.LiveDashboard.RequestLogger.param_key(conn)
    }
  end

  def __plugins__(opts) do
    Keyword.get(opts, :plugins, [])
    |> Phoenix.LiveDashboard.Plugins.load()
  end
end
