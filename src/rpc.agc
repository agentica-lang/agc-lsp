## Reads and writes the JSON-RPC messages of the editor on stdio, with Content-Length framing.

import Logger from "std/logger"

CHUNK_BYTES = 1_048_576
LENGTH_HEADER = "content-length:"
LOG_METHOD = "window/logMessage"
JSONRPC_VERSION = "2.0"

## Names what the input holds next: a message, bytes that are not JSON, a lost framing or the end.
export enum Incoming
  Message(Json)
  Malformed(String)
  Unframed(String)
  End
end

## Holds a successful JSON-RPC response.
export struct Response
  jsonrpc: String
  id: Json
  result: Json
end

## Holds a JSON-RPC notification.
export struct Notification
  jsonrpc: String
  method: String
  params: Json
end

## Returns the next incoming item, waiting for it on standard input.
export def read() -> Incoming
  length = -1
  while true
    line = IO.gets()
    if !line.ok?
      return Incoming.End
    end
    header = line.unwrap!
    if header == ""
      break
    end
    if header.downcase.starts_with?(LENGTH_HEADER)
      length = header.slice(LENGTH_HEADER.length, header.length - LENGTH_HEADER.length).strip.to_i.unwrap_or(-1)
    end
  end
  if length < 0
    return Incoming.Unframed("missing or invalid Content-Length")
  end
  case body(length)
    ok(text) ->
      case JSON.parse(text)
        ok(message) -> return Incoming.Message(message)
        error(message) -> return Incoming.Malformed(message)
      end
    error(message) -> return Incoming.Malformed(message)
  end
end

## Sends the result as the response to the request id.
export def respond(id: Json, result: Json) -> Void
  send(JSON.encode(Response(jsonrpc: JSONRPC_VERSION, id: id, result: result)))
  if Logger.enabled?(LogLevel.Debug)
    Logger.debug("sent a response", {"id": JSON.encode(id)})
  end
end

## Sends an error response with the code and the message to the request id.
export def fail(id: Json, code: Int, message: String) -> Void
  failure: Map[String, Json] = {
    "jsonrpc": JSON.from(JSONRPC_VERSION),
    "id": id,
    "error": JSON.object({"code": JSON.from(code), "message": JSON.from(message)}),
  }
  send(JSON.encode(failure))
  if Logger.enabled?(LogLevel.Debug)
    Logger.debug("sent an error", {"id": JSON.encode(id), "code": code.to_s})
  end
end

## Sends a notification to the editor.
export def notify(method: String, params: Json) -> Void
  send(JSON.encode(Notification(jsonrpc: JSONRPC_VERSION, method: method, params: params)))
  Logger.debug("sent a notification", {"method": method})
end

## Sends a window/logMessage notification with the message type and text.
export def log_message(kind: Int, message: String) -> Void
  params = JSON.object({"type": JSON.from(kind), "message": JSON.from(message)})
  send(JSON.encode(Notification(jsonrpc: JSONRPC_VERSION, method: LOG_METHOD, params: params)))
end

def body(length: Int) -> Result[String]
  data: List[Int] = []
  while data.size < length
    wanted = length - data.size
    if wanted > CHUNK_BYTES
      wanted = CHUNK_BYTES
    end
    chunk = try IO.read_bytes(wanted)
    if chunk.size == 0
      return error("input ended after #{data.size} of #{length} bytes")
    end
    data = data.concat(chunk)
  end
  return String.from_bytes(data)
end

def send(text: String) -> Void
  IO.print("Content-Length: #{text.to_bytes.size}\r\n\r\n#{text}")
  IO.flush()
end
