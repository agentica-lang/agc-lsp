## Checks a whole session of the server through a launcher: `smoke.agc input FILE` writes the messages of an editor
## (initialize, initialized, shutdown, exit) and `smoke.agc verify FILE` checks the replies that the launcher wrote.

TIMEOUT_MS = 20_000
INITIALIZE_ID = 1
SHUTDOWN_ID = 2
LENGTH_PREFIX = "Content-Length: "

def main() -> Void
  args = System.args()
  if args.size != 2
    fail("usage: smoke.agc input|verify FILE")
  end

  case args[0]
    "input" -> finish(write_input(args[1]), "smoke input written")
    "verify" -> finish(verify(args[1]), "smoke ok")
    _ -> fail("unknown command #{args[0]}")
  end
end

def finish(result: Result[Void], done: String) -> Void
  case result
    ok(_) -> puts(done)
    error(message) -> fail(message)
  end
end

def fail(message: String) -> Void
  IO.warn("smoke: #{message}")
  System.exit(1)
end

def write_input(path: String) -> Result[Void]
  initialize = request(INITIALIZE_ID, "initialize", JSON.object({"capabilities": JSON.object({})}))
  messages = [
    frame(initialize),
    frame(notification("initialized")),
    frame(request(SHUTDOWN_ID, "shutdown", JSON.null())),
    frame(notification("exit")),
  ]
  return File.write_text(path, messages.join(""), TIMEOUT_MS)
end

def verify(path: String) -> Result[Void]
  file = try File.open(path, "read", TIMEOUT_MS)
  messages = try read_messages(file)
  initialized = try reply(messages, INITIALIZE_ID)
  capabilities = try JSON.get(try JSON.get(initialized, "result"), "capabilities")
  puts("initialize answered with #{capabilities.to_s}")
  shutdown = try reply(messages, SHUTDOWN_ID)
  result = try JSON.get(shutdown, "result")
  if result.to_s != JSON.null().to_s
    return error("shutdown answered with #{result.to_s}")
  end

  return ok()
end

def request(id: Int, method: String, params: Json) -> String
  return JSON.encode(JSON.object({
    "jsonrpc": JSON.from("2.0"),
    "id": JSON.from(id),
    "method": JSON.from(method),
    "params": params,
  }))
end

def notification(method: String) -> String
  return JSON.encode(JSON.object({
    "jsonrpc": JSON.from("2.0"),
    "method": JSON.from(method),
    "params": JSON.object({}),
  }))
end

def frame(body: String) -> String
  return "#{LENGTH_PREFIX}#{body.to_bytes.size}\r\n\r\n#{body}"
end

def reply(messages: List[Json], id: Int) -> Result[Json]
  for message in messages
    if JSON.get(message, "id").unwrap_or(JSON.null()).to_s == JSON.from(id).to_s
      return ok(message)
    end
  end

  return error("no reply to request #{id} among #{messages.size} messages")
end

def read_messages(file: FileHandle) -> Result[List[Json]]
  messages: List[Json] = []
  while true
    header = File.read_line(file, TIMEOUT_MS)
    if !header.ok?
      return ok(messages)
    end

    messages = messages.push(try read_message(file, header.unwrap!))
  end

  return ok(messages)
end

def read_message(file: FileHandle, header: String) -> Result[Json]
  if !header.starts_with?(LENGTH_PREFIX)
    return error("expected a Content-Length header; got #{header.inspect}")
  end

  length = try header.slice(LENGTH_PREFIX.length, header.length - LENGTH_PREFIX.length).to_i
  blank = try File.read_line(file, TIMEOUT_MS)
  if blank != ""
    return error("expected a blank line after the header; got #{blank.inspect}")
  end

  body = try File.read_bytes(file, length, TIMEOUT_MS)
  return JSON.parse(try String.from_bytes(body))
end
