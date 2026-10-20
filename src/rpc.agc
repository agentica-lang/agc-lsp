CHUNK_BYTES = 1_048_576
LENGTH_HEADER = "content-length:"

export enum Incoming
  Message(Json)
  Malformed(String)
  Unframed(String)
  End
end

export struct Response
  jsonrpc: String
  id: Json
  result: Json
end

export struct Notification
  jsonrpc: String
  method: String
  params: Json
end

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

export def respond(id: Json, result: Json) -> Void
  send(JSON.encode(Response(jsonrpc: "2.0", id: id, result: result)))
end

export def fail(id: Json, code: Int, message: String) -> Void
  failure: Map[String, Json] = {
    "jsonrpc": JSON.from("2.0"),
    "id": id,
    "error": JSON.object({"code": JSON.from(code), "message": JSON.from(message)}),
  }
  send(JSON.encode(failure))
end

export def notify(method: String, params: Json) -> Void
  send(JSON.encode(Notification(jsonrpc: "2.0", method: method, params: params)))
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
