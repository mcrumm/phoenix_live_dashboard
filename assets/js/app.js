import "phoenix_html"
import { Socket, LongPoll } from "phoenix"
import topbar from "../vendor/topbar"
import { LiveSocket } from "phoenix_live_view"
import PhxChartComponent from "./metrics_live"
import PhxRequestLoggerCookie from "./request_logger_cookie"
import PhxRequestLoggerQueryParameter from "./request_logger_query_parameter"
import PhxRequestLoggerMessages from "./request_logger_messages"
import PhxColorBarHighlight from "./color_bar_highlight"
import PhxRememberRefresh from "./remember_refresh"
import { loadRefreshData } from "./refresh";

let Hooks = {
  PhxChartComponent: PhxChartComponent,
  PhxRequestLoggerCookie: PhxRequestLoggerCookie,
  PhxRequestLoggerQueryParameter: PhxRequestLoggerQueryParameter,
  PhxRequestLoggerMessages: PhxRequestLoggerMessages,
  PhxColorBarHighlight: PhxColorBarHighlight,
  PhxRememberRefresh: PhxRememberRefresh
}

let socketPath = document.querySelector("html").getAttribute("phx-socket") || "/live"
let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket(socketPath, Socket, {
  hooks: Hooks,
  params: (liveViewName) => {
    return {
      _csrf_token: csrfToken,
      // Pass the most recent refresh data to the LiveView in `connect_params`
      refresh_data: loadRefreshData(),
    };
  },
})


const socket = liveSocket.socket
const originalOnConnError = socket.onConnError
let fallbackToLongPoll = true

socket.onOpen(() => {
  fallbackToLongPoll = false
})

socket.onConnError = (...args) => {
  if (fallbackToLongPoll) {
    // No longer fallback to longpoll
    fallbackToLongPoll = false
    // close the socket with an error code
    socket.disconnect(null, 3000)
    // fall back to long poll
    socket.transport = LongPoll
    // reopen
    socket.connect()
  } else {
    originalOnConnError.apply(socket, args)
  }
}

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", info => topbar.show())
window.addEventListener("phx:page-loading-stop", info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)
window.liveSocket = liveSocket
