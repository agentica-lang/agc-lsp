import Events from "events"
import Rpc from "rpc"
import Schedule from "schedule"
import Uri from "uri"

PARSE_ERROR = -32700
INVALID_REQUEST = -32600
METHOD_NOT_FOUND = -32601
SERVER_NOT_INITIALIZED = -32002
NO_SYNC = 0
AGENTICA_EXTENSION = ".agc"
EVENT_CAPACITY = 256
WAIT_MS = 1000
READER_CHECK_MS = 1

export struct State
  agentica: String
  encoding: String
  initialized: Bool
  shut_down: Bool
  events: Channel[Events.Event]
  plan: Schedule.Plan
end

enum Next
  Continue(State)
  Exit(Int)
end

export def start(agentica: String) -> State
  events: Channel[Events.Event] = Channel.new(EVENT_CAPACITY)
  return State(
    agentica: agentica,
    encoding: "utf-16",
    initialized: false,
    shut_down: false,
    events: events,
    plan: Schedule.start(agentica, events),
  )
end

export def serve(state: State) -> Int
  reader = Task.spawn(&Events.read_input, state.events)
  current = state
  while true
    case current.events.recv(WAIT_MS)
      ok(event) ->
        case dispatch(current, event)
          Next.Continue(next) -> current = next
          Next.Exit(status) -> return finish(current, reader, status)
        end
      error(_) ->
        if reader_crashed?(reader)
          IO.warn("agc-lsp: the reader of the input crashed")
          return finish(current, reader, 1)
        end
        current = current.with(plan: Schedule.tick(current.plan, current.encoding))
    end
  end
  return finish(current, reader, exit_status(current))
end

def reader_crashed?(reader: Task[Result[Void]]) -> Bool
  case Task.await(reader, READER_CHECK_MS)
    Await.Done(outcome) -> return !outcome.ok?
    Await.TimedOut -> return false
  end
end

def finish(state: State, reader: Task[Result[Void]], status: Int) -> Int
  Task.cancel(reader)
  Schedule.stop(state.plan)
  return status
end

def dispatch(state: State, event: Events.Event) -> Next
  case event
    Events.Event.Checked(report) -> return Next.Continue(checked(state, report))
    Events.Event.Input(incoming) -> return input(state, incoming)
  end
end

def input(state: State, incoming: Rpc.Incoming) -> Next
  case incoming
    Rpc.Incoming.End -> return Next.Exit(exit_status(state))
    Rpc.Incoming.Malformed(message) ->
      Rpc.fail(JSON.null(), PARSE_ERROR, message)
      return Next.Continue(state)
    Rpc.Incoming.Unframed(message) ->
      IO.warn("agc-lsp: #{message}; the stream cannot be read further")
      return Next.Exit(1)
    Rpc.Incoming.Message(message) -> return handle(state, message)
  end
end

def checked(state: State, report: Events.Report) -> State
  if state.shut_down or !Schedule.current?(state.plan, report)
    return state
  end
  if report.outcome.ok?
    publish(report.uri, report.outcome.unwrap!)
  end
  return state.with(plan: Schedule.settle(state.plan, report.uri, state.encoding))
end

def handle(state: State, message: Json) -> Next
  if !object?(message)
    Rpc.fail(JSON.null(), INVALID_REQUEST, "a message must be a JSON object")
    return Next.Continue(state)
  end
  method = JSON.string(JSON.get(message, "method").unwrap_or(JSON.null())).unwrap_or("")
  if method == "exit"
    return Next.Exit(exit_status(state))
  end
  case JSON.get(message, "id")
    ok(id) ->
      if method == "" and response?(message)
        return Next.Continue(state)
      elsif method == ""
        Rpc.fail(id, INVALID_REQUEST, "a request needs a method")
        return Next.Continue(state)
      end
      return Next.Continue(request(state, id, method, params(message)))
    error(_) -> return Next.Continue(notification(state, method, params(message)))
  end
end

def request(state: State, id: Json, method: String, params: Json) -> State
  if !state.initialized and method != "initialize"
    Rpc.fail(id, SERVER_NOT_INITIALIZED, "the server is not initialized")
    return state
  elsif state.shut_down
    Rpc.fail(id, INVALID_REQUEST, "the server is shut down")
    return state
  end
  case method
    "initialize" -> return initialize(state, id, params)
    "shutdown" ->
      Rpc.respond(id, JSON.null())
      return state.with(plan: Schedule.stop(state.plan), shut_down: true)
    _ ->
      Rpc.fail(id, METHOD_NOT_FOUND, "unknown method #{method}")
      return state
  end
end

def initialize(state: State, id: Json, params: Json) -> State
  if state.initialized
    Rpc.fail(id, INVALID_REQUEST, "the server is already initialized")
    return state
  end
  encoding = "utf-16"
  if Set.new(offered(params)).include?("utf-32")
    encoding = "utf-32"
  end
  sync = JSON.object({
    "openClose": JSON.from(true),
    "change": JSON.from(NO_SYNC),
    "save": JSON.object({"includeText": JSON.from(false)}),
  })
  capabilities = JSON.object({"positionEncoding": JSON.from(encoding), "textDocumentSync": sync})
  Rpc.respond(id, JSON.object({
    "capabilities": capabilities,
    "serverInfo": JSON.object({"name": JSON.from("agc-lsp")}),
  }))
  return state.with(encoding: encoding, initialized: true)
end

def notification(state: State, method: String, params: Json) -> State
  if !state.initialized or state.shut_down
    return state
  end
  case method
    "textDocument/didOpen" -> return refresh(state, document_uri(params), true)
    "textDocument/didSave" -> return refresh(state, document_uri(params), true)
    "textDocument/didClose" -> return refresh(state, document_uri(params), false)
    _ -> return state
  end
end

def refresh(state: State, uri: String, checking: Bool) -> State
  path = ""
  case Uri.path_of(uri)
    ok(found) -> path = found
    error(message) ->
      IO.warn("agc-lsp: #{message}")
      return state
  end
  if !path.ends_with?(AGENTICA_EXTENSION)
    return state
  end
  if checking
    return state.with(plan: Schedule.request(state.plan, uri, path, state.encoding))
  end
  none: List[Json] = []
  publish(uri, none)
  return state.with(plan: Schedule.forget(state.plan, uri, state.encoding))
end

def publish(uri: String, found: List[Json]) -> Void
  Rpc.notify("textDocument/publishDiagnostics", JSON.object({
    "uri": JSON.from(uri),
    "diagnostics": JSON.array(found),
  }))
end

def offered(params: Json) -> List[String]
  capabilities = JSON.get(params, "capabilities").unwrap_or(JSON.null())
  general = JSON.get(capabilities, "general").unwrap_or(JSON.null())
  none: List[Json] = []
  encodings = JSON.list(JSON.get(general, "positionEncodings").unwrap_or(JSON.null())).unwrap_or(none)
  names: List[String] = []
  for encoding in encodings
    names = names.push(JSON.string(encoding).unwrap_or(""))
  end
  return names
end

def document_uri(params: Json) -> String
  document = JSON.get(params, "textDocument").unwrap_or(JSON.null())
  return JSON.string(JSON.get(document, "uri").unwrap_or(JSON.null())).unwrap_or("")
end

def response?(message: Json) -> Bool
  return JSON.get(message, "result").ok? or JSON.get(message, "error").ok?
end

def object?(message: Json) -> Bool
  return JSON.encode(message).starts_with?("{")
end

def params(message: Json) -> Json
  return JSON.get(message, "params").unwrap_or(JSON.null())
end

def exit_status(state: State) -> Int
  if state.shut_down
    return 0
  end
  return 1
end
