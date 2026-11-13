## Reads and writes the JSON-RPC messages of the editor on stdio, with Content-Length framing.

import Logger from "std/logger"

## Names what the input holds next: a message, bytes that are not JSON, a lost framing or the end.
enum Incoming
  ## Is a parsed JSON message.
  Message(JSON.Value)
  ## Is a framed body that is not JSON, with the reason.
  Malformed(String)
  ## Is a lost framing, with the reason.
  Unframed(String)
  ## Is the end of the input.
  End
end

## Returns the next incoming item, waiting for it on standard input.
def read() -> Incoming
  length = -1
  while true
    case IO.gets()
      ok(header) ->
        if header == ""
          break
        end

        if header.downcase.start_with?(LENGTH_HEADER)
          length = header.slice(LENGTH_HEADER.length, header.length - LENGTH_HEADER.length).strip.to_i.unwrap_or(-1)
        end

      error(_) -> return Incoming.End
    end
  end

  if length < 0
    return Incoming.Unframed("missing or invalid Content-Length")
  end

  case body(length)
    ok(text) ->
      case JSON.parse(text)
        ok(message) -> return Incoming.Message(message)
        error(failure) -> return Incoming.Malformed(failure.message)
      end

    error(failure) -> return Incoming.Malformed(failure.message)
  end
end

## Sends the result as the response to the request id.
def respond(id: JSON.Value, result: JSON.Value) -> Void
  send(JSON.encode(Response(jsonrpc: JSONRPC_VERSION, id: id, result: result)))
  if Logger.enabled?(Logger.Level.Debug)
    Logger.debug("sent a response", {"id": JSON.encode(id)})
  end
end

## Sends an error response with the code and the message to the request id.
def fail(id: JSON.Value, code: Int, message: String) -> Void
  failure: Map[String, JSON.Value] = {
    "jsonrpc": JSON.from(JSONRPC_VERSION),
    "id": id,
    "error": JSON.object({"code": JSON.from(code), "message": JSON.from(message)}),
  }
  send(JSON.encode(failure))
  if Logger.enabled?(Logger.Level.Debug)
    Logger.debug("sent an error", {"id": JSON.encode(id), "code": code.to_s})
  end
end

## Sends a notification to the editor.
def notify(method: String, params: JSON.Value) -> Void
  send(JSON.encode(Notification(jsonrpc: JSONRPC_VERSION, method: method, params: params)))
  Logger.debug("sent a notification", {"method": method})
end

## Sends a window/logMessage notification with the message type and text.
def log_message(kind: Int, message: String) -> Void
  params = JSON.object({"type": JSON.from(kind), "message": JSON.from(message)})
  send(JSON.encode(Notification(jsonrpc: JSONRPC_VERSION, method: LOG_METHOD, params: params)))
end

private

CHUNK_BYTES = 1_048_576

LENGTH_HEADER = "content-length:"

LOG_METHOD = "window/logMessage"

JSONRPC_VERSION = "2.0"

struct Response
  jsonrpc: String
  id: JSON.Value
  result: JSON.Value
end

struct Notification
  jsonrpc: String
  method: String
  params: JSON.Value
end

def body(length: Int) -> Result[String]
  chunks: List[Bytes] = []
  received = 0
  while received < length
    wanted = length - received
    if wanted > CHUNK_BYTES
      wanted = CHUNK_BYTES
    end

    chunk = try IO.read_bytes(wanted)
    if chunk.size == 0
      return error("input ended after #{received} of #{length} bytes")
    end

    chunks = chunks.push(chunk)
    received += chunk.size
  end

  return String.from_bytes(Bytes.concat(chunks))
end

def send(text: String) -> Void
  IO.print("Content-Length: #{text.bytes.size}\r\n\r\n#{text}")
  IO.flush()
end
