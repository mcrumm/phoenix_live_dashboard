defmodule Phoenix.LiveDashboard.LayoutView do
  @moduledoc false
  use Phoenix.LiveDashboard.Web, :view

  js_path = Path.join(__DIR__, "../../../priv/static/assets/app.js")
  css_path = Path.join(__DIR__, "../../../priv/static/assets/app.css")

  @external_resource js_path
  @external_resource css_path

  @app_js File.read!(js_path)
  @app_css File.read!(css_path)

  def render("app.js", _), do: @app_js
  def render("app.css", _), do: @app_css

  defp csp_nonce(conn, type) when type in [:script, :style, :img] do
    csp_nonce_assign_key = conn.private.csp_nonce_assign_key[type]

    if csp_nonce = conn.assigns[csp_nonce_assign_key] do
      raw("nonce=\"#{csp_nonce}\"")
    end
  end

  def live_socket_path(conn) do
    [Enum.map(conn.script_name, &["/" | &1]) | conn.private.live_socket_path]
  end
end
