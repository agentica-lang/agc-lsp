import Check from "check"
import Rpc from "rpc"
import Uri from "uri"

PARSE_ERROR = -32700
INVALID_REQUEST = -32600
METHOD_NOT_FOUND = -32601
SERVER_NOT_INITIALIZED = -32002
NO_SYNC = 0

export struct State
  agentica: String
  encoding: String
  initialized: Bool
  shut_down: Bool
end

enum Next
  Continue(State)
  Exit(Int)
end

export def start(agentica: String) -> State
  return State(agentica: agentica, encoding: "utf-16", initialized: false, shut_down: false)
end

export def serve(state: State) -> Int
  current = state
  while true
    case Rpc.read()
      Rpc.Incoming.End -> return exit_status(current)
      Rpc.Incoming.Malformed(message) -> Rpc.fail(JSON.null(), PARSE_ERROR, message)
      Rpc.Incoming.Message(message) ->
        case handle(current, message)
          Next.Continue(next) -> current = next
          Next.Exit(status) -> return status
        end
    end
  end
  return exit_status(current)
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
      if method == ""
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
      return state.with(shut_down: true)
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
    "textDocument/didOpen" -> publish(state, document_uri(params), true)
    "textDocument/didSave" -> publish(state, document_uri(params), true)
    "textDocument/didClose" -> publish(state, document_uri(params), false)
    _ -> return state
  end
  return state
end

def publish(state: State, uri: String, checked: Bool) -> Void
  found: List[Json] = []
  if checked
    case Uri.path_of(uri)
      ok(path) -> found = Check.diagnostics(state.agentica, path, state.encoding)
      error(message) ->
        IO.warn("agc-lsp: #{message}")
        return
    end
  end
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
