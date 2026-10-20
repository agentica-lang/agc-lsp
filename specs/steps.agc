import BDD from "std/bdd"

SERVER = "src/main.agc"
TIMEOUT_MS = 20000
DIRECTIVE = "> "

struct Session
  messages: List[Json]
  exit_code: Int
  stderr: String
end

def main() -> Void
  BDD.run([
    BDD.step("an empty folder", &empty_folder),
    BDD.step("the file {string}:", &write_file),
    BDD.step("the client runs the session:", &run_session),
    BDD.step("the server answers request {int} with:", &answers_with),
    BDD.step("the server answers request {int} with the error code {int}", &answers_error),
    BDD.step("the server answers with a parse error", &answers_parse_error),
    BDD.step("the diagnostics published for {string} are, in order:", &published),
    BDD.step("the server exits with code {int}", &exits_with),
  ])
end

def empty_folder(ctx: BDD.Context, _args: List[String]) -> BDD.Context
  base = System.env("TMPDIR").unwrap_or("/tmp")
  name = "agc-lsp-#{Time.now_ms()}-#{Random.int(0, 999_999_999)}"
  path = Path.join([base, name]).unwrap!
  made = Dir.mkdir_private(path, TIMEOUT_MS)
  if !made.ok?
    return BDD.assert(ctx, false, "cannot make #{path}: #{made.message}")
  end
  return BDD.set(ctx, "dir", JSON.from(Path.real(path).unwrap!))
end

def write_file(ctx: BDD.Context, args: List[String]) -> BDD.Context
  path = Path.join([folder(ctx), args[0]]).unwrap!
  written = File.write_text(path, BDD.doc_string(ctx), TIMEOUT_MS)
  return BDD.assert(ctx, written.ok?, "cannot write #{path}: #{written.message}")
end

def run_session(ctx: BDD.Context, _args: List[String]) -> BDD.Context
  dir = folder(ctx)
  ran = session(dir, expand(BDD.doc_string(ctx), dir))
  _ = Path.remove(dir, TIMEOUT_MS)
  case ran
    ok(done) ->
      with_messages = BDD.set(ctx, "messages", JSON.array(done.messages))
      with_exit = BDD.set(with_messages, "exit", JSON.from(done.exit_code))
      return BDD.set(with_exit, "stderr", JSON.from(done.stderr))
    error(message) -> return BDD.assert(ctx, false, message)
  end
end

def answers_with(ctx: BDD.Context, args: List[String]) -> BDD.Context
  expected = canonical(BDD.doc_string(ctx))
  case reply_field(ctx, args[0].to_i!, "result")
    ok(result) -> return BDD.assert(ctx, result.to_s == expected, "expected #{expected}; actual #{result}")
    error(message) -> return BDD.assert(ctx, false, message)
  end
end

def answers_error(ctx: BDD.Context, args: List[String]) -> BDD.Context
  case reply_field(ctx, args[0].to_i!, "error")
    ok(found) ->
      code = JSON.get(found, "code").unwrap_or(JSON.null()).to_s
      return BDD.assert(ctx, code == args[1], "expected error code #{args[1]}; actual #{found}")
    error(message) -> return BDD.assert(ctx, false, message)
  end
end

def answers_parse_error(ctx: BDD.Context, _args: List[String]) -> BDD.Context
  for message in messages(ctx)
    id = JSON.get(message, "id")
    code = at(message, ["error", "code"])
    if id.ok? and JSON.null?(id.unwrap!) and code.ok? and code.unwrap!.to_s == "-32700"
      return BDD.assert(ctx, true, "")
    end
  end
  return BDD.assert(ctx, false, "no parse error among #{JSON.array(messages(ctx))}")
end

def published(ctx: BDD.Context, args: List[String]) -> BDD.Context
  uri = "file://#{folder(ctx)}/#{args[0]}"
  expected = canonical(expand(BDD.doc_string(ctx), folder(ctx)))
  lists: List[Json] = []
  for message in messages(ctx)
    if notification_for?(message, uri)
      lists = lists.push(JSON.get(JSON.get(message, "params").unwrap!, "diagnostics").unwrap!)
    end
  end
  actual = JSON.array(lists).to_s
  return BDD.assert(ctx, actual == expected, "expected #{expected}; actual #{actual}; stderr #{stderr(ctx)}")
end

def exits_with(ctx: BDD.Context, args: List[String]) -> BDD.Context
  code = JSON.int(BDD.get(ctx, "exit").unwrap!).unwrap!
  return BDD.assert(ctx, code == args[0].to_i!, "expected exit code #{args[0]}; actual #{code}; stderr #{stderr(ctx)}")
end

def session(dir: String, script: String) -> Result[Session]
  server = try Process.spawn_captured("agentica", ["--allow-run", SERVER], ".", TIMEOUT_MS)
  received: List[Json] = []
  for line in script.split("\n")
    if line.strip.length == 0
      next
    elsif line.starts_with?(DIRECTIVE)
      received = received.concat(try directive(server, dir, line.slice(2, line.length - 2)))
    else
      try Process.send(server, frame(line), TIMEOUT_MS)
    end
  end
  try Process.close_stdin(server, TIMEOUT_MS)
  received = received.concat(try read_rest(server))
  exit_code = try Process.wait(server, TIMEOUT_MS)
  output = try Process.output(server, TIMEOUT_MS)
  return ok(Session(messages: received, exit_code: exit_code, stderr: output.stderr))
end

def directive(server: Process, dir: String, text: String) -> Result[List[Json]]
  if text == "await diagnostics"
    return read_until_diagnostics(server)
  end
  words = text.split(" ")
  if words.size == 4 and words[0] == "copy" and words[2] == "to"
    source = try File.read_text(try Path.join([dir, words[1]]), TIMEOUT_MS)
    try File.write_text(try Path.join([dir, words[3]]), source, TIMEOUT_MS)
    return ok([])
  end
  return error("unknown directive: #{text}")
end

def read_rest(server: Process) -> Result[List[Json]]
  received: List[Json] = []
  while true
    header = Process.read_line(server, TIMEOUT_MS)
    if !header.ok?
      return ok(received)
    end
    received = received.push(try read_body(server, header.unwrap!))
  end
  return ok(received)
end

def read_until_diagnostics(server: Process) -> Result[List[Json]]
  received: List[Json] = []
  while true
    message = try read_body(server, try Process.read_line(server, TIMEOUT_MS))
    received = received.push(message)
    method = at(message, ["method"])
    if method.ok? and method.unwrap!.to_s == JSON.from("textDocument/publishDiagnostics").to_s
      return ok(received)
    end
  end
  return ok(received)
end

def read_body(server: Process, header: String) -> Result[Json]
  prefix = "Content-Length: "
  if !header.starts_with?(prefix)
    return error("expected a Content-Length header; got #{header.inspect}")
  end
  length = try header.slice(prefix.length, header.length - prefix.length).to_i
  blank = try Process.read_line(server, TIMEOUT_MS)
  if blank != ""
    return error("expected a blank line after the header; got #{blank.inspect}")
  end
  body = try Process.read_bytes(server, length, TIMEOUT_MS)
  return JSON.parse(try String.from_bytes(body))
end

def frame(body: String) -> String
  return "Content-Length: #{body.to_bytes.size}\r\n\r\n#{body}"
end

def expand(text: String, dir: String) -> String
  return text.replace("${URI}", "file://#{dir}").replace("${DIR}", dir)
end

def canonical(text: String) -> String
  return JSON.parse(text).unwrap!.to_s
end

def reply_field(ctx: BDD.Context, id: Int, field: String) -> Result[Json]
  for message in messages(ctx)
    found = JSON.get(message, "id")
    if found.ok? and found.unwrap!.to_s == id.to_s
      return JSON.get(message, field)
    end
  end
  return error("no reply to request #{id} among #{JSON.array(messages(ctx))}")
end

def notification_for?(message: Json, uri: String) -> Bool
  method = at(message, ["method"])
  target = at(message, ["params", "uri"])
  return (
    method.ok? and method.unwrap!.to_s == JSON.from("textDocument/publishDiagnostics").to_s
    and target.ok? and target.unwrap!.to_s == JSON.from(uri).to_s
  )
end

def at(value: Json, keys: List[String]) -> Result[Json]
  found = value
  for key in keys
    found = try JSON.get(found, key)
  end
  return ok(found)
end

def folder(ctx: BDD.Context) -> String
  return JSON.string(BDD.get(ctx, "dir").unwrap!).unwrap!
end

def messages(ctx: BDD.Context) -> List[Json]
  return JSON.list(BDD.get(ctx, "messages").unwrap!).unwrap!
end

def stderr(ctx: BDD.Context) -> String
  return JSON.string(BDD.get(ctx, "stderr").unwrap!).unwrap!
end
