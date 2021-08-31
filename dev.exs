# iex -S mix dev
Logger.configure(level: :debug)

pg_url = System.get_env("PG_URL") || "postgres:postgres@127.0.0.1"
pg_database = System.get_env("PG_DATABASE") || "phx_dashboard_dev"
Application.put_env(:phoenix_live_dashboard, Demo.Repo, url: "ecto://#{pg_url}/#{pg_database}")

defmodule Demo.Repo do
  use Ecto.Repo, otp_app: :phoenix_live_dashboard, adapter: Ecto.Adapters.Postgres
end

_ = Ecto.Adapters.Postgres.storage_up(Demo.Repo.config())

# Configures the endpoint
Application.put_env(:phoenix_live_dashboard, DemoWeb.Endpoint,
  url: [host: "localhost"],
  secret_key_base: "Hu4qQN3iKzTV4fJxhorPQlA/osH9fAMtbtjVS58PFgfw3ja5Z18Q/WSNR9wP4OfW",
  live_view: [signing_salt: "hMegieSe"],
  http: [ip: {127, 0, 0, 1}, port: System.get_env("PORT") || 4000],
  debug_errors: true,
  check_origin: false,
  pubsub_server: Demo.PubSub,
  watchers: [
    esbuild: {
      Esbuild,
      :install_and_run,
      [:default, ~w(--sourcemap=inline --watch)]
    },
    sass: {
      DartSass,
      :install_and_run,
      [:default, ~w(--embed-source-map --source-map-urls=absolute --watch)]
    }
  ],
  live_reload: [
    patterns: [
      ~r"priv/static/assets/.*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"lib/phoenix/live_dashboard/(live|views)/.*(ex)$",
      ~r"lib/phoenix/live_dashboard/templates/.*(ex)$"
    ]
  ]
)

defmodule DemoWeb.History do
  use GenServer

  @history_buffer_size 50

  def data(metric) do
    GenServer.call(__MODULE__, {:data, metric})
  end

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl true
  def init(metrics) do
    Process.flag(:trap_exit, true)

    metric_histories_map =
      metrics
      |> Enum.map(fn metric ->
        attach_handler(metric)
        {metric, CircularBuffer.new(@history_buffer_size)}
      end)
      |> Map.new()

    {:ok, metric_histories_map}
  end

  @impl true
  def terminate(_, metrics) do
    for {metric, _} <- metrics do
      :telemetry.detach({__MODULE__, metric, self()})
    end

    :ok
  end

  defp attach_handler(%{name: name_list} = metric) do
    :telemetry.attach(
      {__MODULE__, metric, self()},
      Enum.slice(name_list, 0, length(name_list) - 1),
      &__MODULE__.handle_event/4,
      metric
    )
  end

  def handle_event(_event_name, data, metadata, metric) do
    if data = Phoenix.LiveDashboard.extract_datapoint_for_metric(metric, data, metadata) do
      GenServer.cast(__MODULE__, {:telemetry_metric, data, metric})
    end
  end

  @impl true
  def handle_cast({:telemetry_metric, data, metric}, state) do
    {:noreply, update_in(state[metric], &CircularBuffer.insert(&1, data))}
  end

  @impl true
  def handle_call({:data, metric}, _from, state) do
    if history = state[metric] do
      {:reply, CircularBuffer.to_list(history), state}
    else
      {:reply, [], state}
    end
  end
end

defmodule DemoWeb.Telemetry do
  import Telemetry.Metrics

  def metrics do
    [
      # Phoenix Metrics
      last_value("phoenix.endpoint.stop.duration",
        description: "Last value of phoenix.endpoint response time",
        unit: {:native, :millisecond}
      ),
      counter("phoenix.endpoint.stop.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.endpoint.stop.duration",
        unit: {:native, :microsecond}
      ),
      last_value("phoenix.router_dispatch.stop.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      counter("phoenix.router_dispatch.stop.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.stop.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),

      # VM Metrics
      summary("vm.memory.total", unit: {:byte, :kilobyte}),
      summary("vm.total_run_queue_lengths.total"),
      summary("vm.total_run_queue_lengths.cpu"),
      summary("vm.total_run_queue_lengths.io")
    ]
  end
end

defmodule DemoWeb.PageController do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, :index) do
    content(conn, """
    <h2>Phoenix LiveDashboard Dev</h2>
    <a href="/dashboard" target="_blank">Open Dashboard</a>
    """)
  end

  def call(conn, :hello) do
    name = Map.get(conn.params, "name", "friend")
    content(conn, "<p>Hello, #{name}!</p>")
  end

  defp content(conn, content) do
    conn
    |> put_resp_header("content-type", "text/html")
    |> send_resp(200, "<!doctype html><html><body>#{content}</body></html>")
  end
end

defmodule DemoWeb.GraphShowcasePage do
  use Phoenix.LiveDashboard.PageBuilder, refresher?: false

  @impl true
  def menu_link(_, _) do
    {:ok, "Graph component"}
  end

  @impl true
  def mount(_params, _, socket) do
    {:ok, socket}
  end

  @impl true
  def render_page(_assigns) do
    items = [
      simple_graph: [name: "Simple", render: &simple/0],
      groups_graph: [name: "Groups", render: &two_groups/0],
      groups_with_intercalation_graph: [
        name: "Groups with intercalation",
        render: &two_groups_intercalation/0
      ],
      broadway_graph: [name: "Broadway graph", render: &broadway_graph/0],
      wider_graph: [name: "Wider graph", render: &wider_graph/0]
    ]

    nav_bar(items: items)
  end

  defp simple do
    layered_graph(
      title: "Simple graph",
      layers: [
        [%{id: "a1", data: "a1", children: ["b1", "b2"]}],
        [%{id: "b1", data: "b1", children: ["c1"]}, %{id: "b2", data: "b2", children: ["c1"]}],
        [%{id: "c1", data: "c1", children: []}]
      ]
    )
  end

  defp two_groups do
    background = fn data -> if String.starts_with?(data, "a"), do: "#5d89c7", else: "#555" end

    layered_graph(
      title: "Two groups",
      background: background,
      hint: "This chart shows that we can have groups based on parent nodes.",
      layers: [
        [
          %{id: "a1", data: "a1", children: ["b1", "b2"]},
          %{id: "a2", data: "a2", children: ["b3", "b4"]},
          %{id: "a3", data: "a3", children: ["b3", "b4"]},
          %{id: "a4", data: "a4", children: ["b3", "b4"]},
          %{id: "a5", data: "a5", children: ["b3", "b4"]}
        ],
        [
          %{id: "b1", data: "b1", children: []},
          %{id: "b2", data: "b2", children: []},
          %{id: "b3", data: "b3", children: []},
          %{id: "b4", data: "b4", children: []}
        ]
      ]
    )
  end

  defp two_groups_intercalation do
    format_label = &String.upcase/1

    layered_graph(
      title: "Two groups with intercalation",
      hint: "This chart shows that intercalation of children is correctly displayed.",
      format_label: format_label,
      layers: [
        [
          %{id: "a1", data: "a1", children: ["b1", "b3", "b5"]},
          %{id: "a2", data: "a2", children: ["b2", "b4", "b6"]}
        ],
        [
          %{id: "b1", data: "b1", children: []},
          %{id: "b2", data: "b2", children: []},
          %{id: "b3", data: "b3", children: []},
          %{id: "b4", data: "b4", children: []},
          %{id: "b5", data: "b5", children: []},
          %{id: "b6", data: "b6", children: []}
        ]
      ]
    )
  end

  defp broadway_graph do
    background = fn data ->
      case data do
        %{detail: perc} ->
          hue = 100 - perc

          "hsl(#{hue}, 80%, 35%)"

        _ ->
          "lightgray"
      end
    end

    format_detail = fn data -> "#{data.detail}%" end

    layers = [
      [
        %{
          children: [
            Demo.Pipeline.Broadway.Processor_default_0,
            Demo.Pipeline.Broadway.Processor_default_1,
            Demo.Pipeline.Broadway.Processor_default_2,
            Demo.Pipeline.Broadway.Processor_default_3,
            Demo.Pipeline.Broadway.Processor_default_4
          ],
          data: "prod_0",
          id: Demo.Pipeline.Broadway.Producer_0
        }
      ],
      [
        %{
          children: [Demo.Pipeline.Broadway.Batcher_default],
          data: %{detail: 84, label: "proc_0"},
          id: Demo.Pipeline.Broadway.Processor_default_0
        },
        %{
          children: [Demo.Pipeline.Broadway.Batcher_default],
          data: %{detail: 13, label: "proc_1"},
          id: Demo.Pipeline.Broadway.Processor_default_1
        },
        %{
          children: [Demo.Pipeline.Broadway.Batcher_default],
          data: %{detail: 80, label: "proc_2"},
          id: Demo.Pipeline.Broadway.Processor_default_2
        },
        %{
          children: [Demo.Pipeline.Broadway.Batcher_default],
          data: %{detail: 82, label: "proc_3"},
          id: Demo.Pipeline.Broadway.Processor_default_3
        },
        %{
          children: [Demo.Pipeline.Broadway.Batcher_default],
          data: %{detail: 40, label: "proc_4"},
          id: Demo.Pipeline.Broadway.Processor_default_4
        }
      ],
      [
        %{
          children: [
            Demo.Pipeline.Broadway.BatchProcessor_default_0,
            Demo.Pipeline.Broadway.BatchProcessor_default_1,
            Demo.Pipeline.Broadway.BatchProcessor_default_2
          ],
          data: %{detail: 33, label: "default"},
          id: Demo.Pipeline.Broadway.Batcher_default
        }
      ],
      [
        %{
          children: [],
          data: %{detail: 61, label: "proc_0"},
          id: Demo.Pipeline.Broadway.BatchProcessor_default_0
        },
        %{
          children: [],
          data: %{detail: 61, label: "proc_1"},
          id: Demo.Pipeline.Broadway.BatchProcessor_default_1
        },
        %{
          children: [],
          data: %{detail: 53, label: "proc_2"},
          id: Demo.Pipeline.Broadway.BatchProcessor_default_2
        }
      ]
    ]

    layered_graph(
      layers: layers,
      background: background,
      format_detail: format_detail,
      title: "Broadway graph"
    )
  end

  defp wider_graph do
    bottom_layer = for i <- 1..20, do: %{id: "b#{i}", data: "b#{i}", children: []}

    layered_graph(
      title: "Simple graph",
      layers: [
        [%{id: "a1", data: "a1", children: Enum.map(1..20, &"b#{&1}")}],
        bottom_layer
      ]
    )
  end
end

defmodule DemoWeb.Router do
  use Phoenix.Router
  import Phoenix.LiveDashboard.Router

  pipeline :browser do
    plug :fetch_session
    # plug :put_csp
  end

  scope "/" do
    pipe_through :browser
    get "/", DemoWeb.PageController, :index
    get "/hello", DemoWeb.PageController, :hello
    get "/hello/:name", DemoWeb.PageController, :hello

    live_dashboard("/dashboard",
      env_keys: ["USER", "ROOTDIR"],
      metrics: DemoWeb.Telemetry,
      metrics_history: {DemoWeb.History, :data, []},
      allow_destructive_actions: true,
      ecto_repos: [Demo.Repo],
      home_app: {"Erlang's stdlib", :stdlib},
      additional_pages: [
        components: DemoWeb.GraphShowcasePage
      ],
      csp_nonce_assign_key: %{
        img: :img_csp_nonce,
        style: :style_csp_nonce,
        script: :script_csp_nonce
      },
      ecto_psql_extras_options: [
        long_running_queries: [threshold: "200 milliseconds"]
      ]
    )
  end

  def put_csp(conn, _opts) do
    [img_nonce, style_nonce, script_nonce] =
      for _i <- 1..3, do: 16 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

    conn
    |> assign(:img_csp_nonce, img_nonce)
    |> assign(:style_csp_nonce, style_nonce)
    |> assign(:script_csp_nonce, script_nonce)
    |> put_resp_header(
      "content-security-policy",
      "default-src; script-src 'nonce-#{script_nonce}'; style-src 'nonce-#{style_nonce}'; " <>
        "img-src 'nonce-#{img_nonce}' data: ; font-src data: ; connect-src 'self'; frame-src 'self' ;"
    )
  end
end

defmodule DemoWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :phoenix_live_dashboard

  socket "/live", Phoenix.LiveView.Socket
  socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket

  plug Phoenix.LiveReloader
  plug Phoenix.CodeReloader

  plug Phoenix.LiveDashboard.RequestLogger,
    param_key: "request_logger",
    cookie_key: "request_logger"

  plug Plug.Session,
    store: :cookie,
    key: "_live_view_key",
    signing_salt: "/VEDsdfsffMnp5"

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]
  plug DemoWeb.Router
end

Application.ensure_all_started(:os_mon)
Application.put_env(:phoenix, :serve_endpoints, true)

Task.async(fn ->
  children = [
    Demo.Repo,
    {Phoenix.PubSub, [name: Demo.PubSub, adapter: Phoenix.PubSub.PG2]},
    {DemoWeb.History, DemoWeb.Telemetry.metrics()},
    DemoWeb.Endpoint
  ]

  {:ok, _} = Supervisor.start_link(children, strategy: :one_for_one)
  Process.sleep(:infinity)
end)
|> Task.await(:infinity)
