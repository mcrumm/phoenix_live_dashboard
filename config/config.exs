use Mix.Config

config :phoenix, :json_library, Jason
config :phoenix, :stacktrace_depth, 20

config :logger, level: :warn
config :logger, :console, format: "[$level] $message\n"

if Mix.env() == :dev do
  config :esbuild,
    version: "0.12.17",
    default: [
      args: ~w(js/app.js --bundle --target=es2016 --outdir=../priv/static/assets),
      cd: Path.expand("../assets", __DIR__),
      env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
    ]

  config :dart_sass,
    version: "1.36.0",
    default: [
      args: ~w(css/app.scss ../priv/static/assets/app.css),
      cd: Path.expand("../assets", __DIR__)
    ]
end
