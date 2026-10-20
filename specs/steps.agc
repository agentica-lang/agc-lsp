import BDD from "std/bdd"

SERVER = "src/main.agc"
TIMEOUT_MS = 20000
LOCALHOST = "localhost"
PUBLISH = "textDocument/publishDiagnostics"
SEVERITIES = {"error": 1, "warning": 2, "information": 3, "hint": 4}
ERROR_CODES = {
  "parse error": -32700,
  "invalid request": -32600,
  "method not found": -32601,
  "server not initialized": -32002,
}

struct Session
  messages: List[Json]
  exit_code: Int
  stderr: String
end

def main() -> Void
  BDD.run([
    BDD.step("the language server has started", &started),
    BDD.step("the language server has started with the position encodings {string}", &started_with),
    BDD.step("the language server has started with the arguments {string}", &started_with_arguments),
    BDD.step("the file {string} contains:", &file_contains),
    BDD.step("the editor opens {string}", &opens),
    BDD.step("the editor opens {string} through a localhost URI", &opens_through_localhost),
    BDD.step("the editor saves {string} as:", &saves_as),
    BDD.step("the editor closes {string}", &closes),
    BDD.step("the editor sends {string} before initializing", &sends_request),
    BDD.step("the editor sends the request {string}", &sends_request),
    BDD.step("the editor sends a message that is not JSON", &sends_garbage),
    BDD.step("the editor sends the raw message:", &sends_raw),
    BDD.step("the editor exits without shutting down", &exits_early),
    BDD.step("the editor closes the connection", &hangs_up),
    BDD.step("the client runs the session:", &run_session),
    BDD.step("the server answers request {int} with:", &answers_with),
    BDD.step("the server announces the position encoding {string}", &announces_encoding),
    BDD.step("the server answers {string} with the error {string}", &answers_error),
    BDD.step("the server answers request {int} with the error {string}", &answers_id_error),
    BDD.step("the server reports the error {string}", &reports_error),
    BDD.step("{string} gets these diagnostics:", &gets_diagnostics),
    BDD.step("{string} through a localhost URI gets these diagnostics:", &gets_diagnostics_through_localhost),
    BDD.step("{string} gets no diagnostics", &gets_none),
    BDD.step("the diagnostic of {string} has a help line", &has_help),
    BDD.step("the diagnostic of {string} points to {string}", &points_to),
    BDD.step("the server exits with code {int}", &exits_with),
  ])
end

def started(ctx: BDD.Context, _args: List[String]) -> BDD.Context
  return initialize(ctx, JSON.object({}))
end

def started_with(ctx: BDD.Context, args: List[String]) -> BDD.Context
  offered = args[0].split(",").map do |name| JSON.from(name.strip) end
  general = JSON.object({"positionEncodings": JSON.array(offered)})
  return initialize(ctx, JSON.object({"general": general}))
end

def started_with_arguments(ctx: BDD.Context, args: List[String]) -> BDD.Context
  words = args[0].split(" ").map do |word| JSON.from(word) end
  return initialize(BDD.set(ctx, "arguments", JSON.array(words)), JSON.object({}))
end

def file_contains(ctx: BDD.Context, args: List[String]) -> BDD.Context
  ready = with_folder(ctx)
  path = file_path(ready, args[0])
  written = File.write_text(path, BDD.doc_string(ready), TIMEOUT_MS)
  return BDD.assert(ready, written.ok?, "cannot write #{path}: #{written.message}")
end

def opens(ctx: BDD.Context, args: List[String]) -> BDD.Context
  return open_through(ctx, args[0], "")
end

def opens_through_localhost(ctx: BDD.Context, args: List[String]) -> BDD.Context
  return open_through(ctx, args[0], LOCALHOST)
end

def open_through(ctx: BDD.Context, name: String, authority: String) -> BDD.Context
  ready = with_folder(ctx)
  text = File.read_text(file_path(ready, name), TIMEOUT_MS).unwrap_or("")
  document = JSON.object({
    "uri": JSON.from(uri(ready, name, authority)),
    "languageId": JSON.from("agentica"),
    "version": JSON.from(1),
    "text": JSON.from(text),
  })
  return notify(ready, "textDocument/didOpen", JSON.object({"textDocument": document}))
end

def saves_as(ctx: BDD.Context, args: List[String]) -> BDD.Context
  ready = with_folder(ctx)
  text = BDD.doc_string(ready)
  document = JSON.object({"uri": JSON.from(uri(ready, args[0])), "version": JSON.from(2)})
  waited = add(ready, JSON.object({"kind": JSON.from("await")}))
  written = add(waited, JSON.object({
    "kind": JSON.from("write"),
    "name": JSON.from(args[0]),
    "text": JSON.from(text),
  }))
  changed = notify(written, "textDocument/didChange", JSON.object({
    "textDocument": document,
    "contentChanges": JSON.array([JSON.object({"text": JSON.from(text)})]),
  }))
  saved = JSON.object({"uri": JSON.from(uri(ready, args[0]))})
  return notify(changed, "textDocument/didSave", JSON.object({"textDocument": saved}))
end

def closes(ctx: BDD.Context, args: List[String]) -> BDD.Context
  document = JSON.object({"uri": JSON.from(uri(ctx, args[0]))})
  return notify(ctx, "textDocument/didClose", JSON.object({"textDocument": document}))
end

def sends_request(ctx: BDD.Context, args: List[String]) -> BDD.Context
  return request(ctx, args[0], JSON.object({}))
end

def sends_garbage(ctx: BDD.Context, _args: List[String]) -> BDD.Context
  return send(ctx, "{not json")
end

def sends_raw(ctx: BDD.Context, _args: List[String]) -> BDD.Context
  return send(ctx, BDD.doc_string(ctx).strip)
end

def exits_early(ctx: BDD.Context, _args: List[String]) -> BDD.Context
  sent = notify(ctx, "exit", JSON.null())
  return BDD.set(sent, "ended", JSON.from(true))
end

def hangs_up(ctx: BDD.Context, _args: List[String]) -> BDD.Context
  return BDD.set(ctx, "ended", JSON.from(true))
end

def run_session(ctx: BDD.Context, _args: List[String]) -> BDD.Context
  actions: List[Json] = []
  for line in BDD.doc_string(ctx).split("\n")
    if line.strip.length > 0
      actions = actions.push(JSON.object({"kind": JSON.from("send"), "body": JSON.from(line)}))
    end
  end
  return record(ctx, run(ctx, actions))
end

def answers_with(ctx: BDD.Context, args: List[String]) -> BDD.Context
  return finished(ctx) do |done| answer_is(done, args[0].to_i!, canonical(BDD.doc_string(done))) end
end

def announces_encoding(ctx: BDD.Context, args: List[String]) -> BDD.Context
  return finished(ctx) do |done| encoding_is(done, args[0]) end
end

def answers_error(ctx: BDD.Context, args: List[String]) -> BDD.Context
  return finished(ctx) do |done| request_failed(done, args[0], args[1]) end
end

def answers_id_error(ctx: BDD.Context, args: List[String]) -> BDD.Context
  return finished(ctx) do |done| id_failed(done, args[0].to_i!, args[1]) end
end

def reports_error(ctx: BDD.Context, args: List[String]) -> BDD.Context
  return finished(ctx) do |done| reported(done, args[0]) end
end

def gets_diagnostics(ctx: BDD.Context, args: List[String]) -> BDD.Context
  rows = BDD.table(ctx).drop(1)
  expected = rows.map do |row| expected_diagnostic(row) end
  return next_publish(ctx, uri(ctx, args[0]), JSON.array(expected))
end

def gets_diagnostics_through_localhost(ctx: BDD.Context, args: List[String]) -> BDD.Context
  expected = BDD.table(ctx).drop(1).map do |row| expected_diagnostic(row) end
  return next_publish(ctx, uri(ctx, args[0], LOCALHOST), JSON.array(expected))
end

def gets_none(ctx: BDD.Context, args: List[String]) -> BDD.Context
  none: List[Json] = []
  return next_publish(ctx, uri(ctx, args[0]), JSON.array(none))
end

def has_help(ctx: BDD.Context, args: List[String]) -> BDD.Context
  return last_message(ctx, args[0]) do |done, message|
    BDD.assert(done, message.contains?("\nhelp: "), "no help line in #{message.inspect}")
  end
end

def points_to(ctx: BDD.Context, args: List[String]) -> BDD.Context
  return last_message(ctx, args[0]) do |done, message|
    BDD.assert(done, message.contains?("/#{args[1]}: "), "#{message.inspect} does not point to #{args[1]}")
  end
end

def exits_with(ctx: BDD.Context, args: List[String]) -> BDD.Context
  return finished(ctx) do |done|
    code = JSON.int(BDD.get(done, "exit").unwrap!).unwrap!
    BDD.assert(done, code == args[0].to_i!, "expected exit code #{args[0]}; actual #{code}; stderr #{stderr(done)}")
  end
end

def answer_is(ctx: BDD.Context, id: Int, expected: String) -> BDD.Context
  case reply(ctx, id, "result")
    ok(result) -> return BDD.assert(ctx, result.to_s == expected, "expected #{expected}; actual #{result}")
    error(message) -> return BDD.assert(ctx, false, message)
  end
end

def encoding_is(ctx: BDD.Context, expected: String) -> BDD.Context
  case reply(ctx, 1, "result")
    ok(result) ->
      actual = at(result, ["capabilities", "positionEncoding"]).unwrap_or(JSON.null()).to_s
      wanted = JSON.from(expected).to_s
      return BDD.assert(ctx, actual == wanted, "expected #{wanted}; actual #{actual}")
    error(message) -> return BDD.assert(ctx, false, message)
  end
end

def request_failed(ctx: BDD.Context, method: String, name: String) -> BDD.Context
  return id_failed(ctx, JSON.int(BDD.get(ctx, "request #{method}").unwrap!).unwrap!, name)
end

def id_failed(ctx: BDD.Context, id: Int, name: String) -> BDD.Context
  case reply(ctx, id, "error")
    ok(found) -> return expect_error(ctx, found, name)
    error(message) -> return BDD.assert(ctx, false, message)
  end
end

def reported(ctx: BDD.Context, name: String) -> BDD.Context
  for message in messages(ctx)
    if at(message, ["id"]).unwrap_or(JSON.from(0)).to_s == "null" and at(message, ["error"]).ok?
      return expect_error(ctx, at(message, ["error"]).unwrap!, name)
    end
  end
  return BDD.assert(ctx, false, "no error without an id among #{JSON.array(messages(ctx))}")
end

def initialize(ctx: BDD.Context, capabilities: Json) -> BDD.Context
  return request(ctx, "initialize", JSON.object({"capabilities": capabilities}))
end

def request(ctx: BDD.Context, method: String, params: Json) -> BDD.Context
  id = JSON.int(BDD.get(ctx, "next_id").unwrap_or(JSON.from(1))).unwrap!
  tracked = BDD.set(ctx, "request #{method}", JSON.from(id))
  counted = BDD.set(tracked, "next_id", JSON.from(id + 1))
  body: Map[String, Json] = {
    "jsonrpc": JSON.from("2.0"),
    "id": JSON.from(id),
    "method": JSON.from(method),
    "params": params,
  }
  return send(counted, JSON.encode(body))
end

def notify(ctx: BDD.Context, method: String, params: Json) -> BDD.Context
  body: Map[String, Json] = {"jsonrpc": JSON.from("2.0"), "method": JSON.from(method), "params": params}
  return send(ctx, JSON.encode(body))
end

def send(ctx: BDD.Context, body: String) -> BDD.Context
  return add(ctx, JSON.object({"kind": JSON.from("send"), "body": JSON.from(body)}))
end

def add(ctx: BDD.Context, action: Json) -> BDD.Context
  none: List[Json] = []
  actions = JSON.list(BDD.get(ctx, "script").unwrap_or(JSON.array(none))).unwrap!
  return BDD.set(ctx, "script", JSON.array(actions.push(action)))
end

def finished(ctx: BDD.Context, check: Fn[BDD.Context, BDD.Context]) -> BDD.Context
  if BDD.get(ctx, "messages").ok?
    return check.call(ctx)
  end
  none: List[Json] = []
  actions = JSON.list(BDD.get(ctx, "script").unwrap_or(JSON.array(none))).unwrap!
  if !BDD.get(ctx, "ended").ok?
    shut = request(BDD.set(ctx, "script", JSON.array(actions)), "shutdown", JSON.null())
    actions = JSON.list(BDD.get(notify(shut, "exit", JSON.null()), "script").unwrap!).unwrap!
  end
  recorded = record(ctx, run(ctx, actions))
  if !BDD.get(recorded, "messages").ok?
    return recorded
  end
  return check.call(recorded)
end

def record(ctx: BDD.Context, ran: Result[Session]) -> BDD.Context
  case ran
    ok(done) ->
      with_messages = BDD.set(ctx, "messages", JSON.array(done.messages))
      with_exit = BDD.set(with_messages, "exit", JSON.from(done.exit_code))
      return BDD.set(with_exit, "stderr", JSON.from(done.stderr))
    error(message) -> return BDD.assert(ctx, false, message)
  end
end

def next_publish(ctx: BDD.Context, target: String, expected: Json) -> BDD.Context
  return finished(ctx) do |done| publish_is(done, target, expected) end
end

def publish_is(ctx: BDD.Context, target: String, expected: Json) -> BDD.Context
  key = "seen #{target}"
  seen = JSON.int(BDD.get(ctx, key).unwrap_or(JSON.from(0))).unwrap!
  lists = published(ctx, target)
  if seen >= lists.size
    return BDD.assert(ctx, false, "#{target} got #{lists.size} publishes, expected one more; stderr #{stderr(ctx)}")
  end
  actual = canonical(JSON.encode(JSON.array(lists[seen].map do |found| without_message(found) end)))
  wanted = canonical(JSON.encode(expected))
  counted = BDD.set(ctx, key, JSON.from(seen + 1))
  return BDD.assert(counted, actual == wanted, "expected #{wanted}; actual #{actual}")
end

def last_message(ctx: BDD.Context, name: String, check: Fn[BDD.Context, String, BDD.Context]) -> BDD.Context
  return finished(ctx) do |done| message_of(done, name, check) end
end

def message_of(ctx: BDD.Context, name: String, check: Fn[BDD.Context, String, BDD.Context]) -> BDD.Context
  lists = published(ctx, uri(ctx, name))
  if lists.size == 0 or lists[lists.size - 1].size == 0
    return BDD.assert(ctx, false, "#{name} has no diagnostic")
  end
  return check.call(ctx, JSON.string(at(lists[lists.size - 1][0], ["message"]).unwrap!).unwrap!)
end

def published(ctx: BDD.Context, sent: String) -> List[List[Json]]
  target = JSON.from(sent).to_s
  lists: List[List[Json]] = []
  for message in messages(ctx)
    method = at(message, ["method"]).unwrap_or(JSON.null()).to_s
    if method == JSON.from(PUBLISH).to_s and at(message, ["params", "uri"]).unwrap_or(JSON.null()).to_s == target
      lists = lists.push(JSON.list(at(message, ["params", "diagnostics"]).unwrap!).unwrap!)
    end
  end
  return lists
end

def expected_diagnostic(row: List[String]) -> Json
  edges = row[0].split("-")
  return JSON.object({
    "range": JSON.object({"start": position(edges[0]), "end": position(edges[1])}),
    "severity": JSON.from(SEVERITIES.get(row[1]).unwrap!),
    "code": JSON.from(row[2]),
    "source": JSON.from("agentica"),
  })
end

def position(text: String) -> Json
  parts = text.split(":")
  return JSON.object({
    "line": JSON.from(parts[0].to_i! - 1),
    "character": JSON.from(parts[1].to_i! - 1),
  })
end

def without_message(found: Json) -> Json
  fields: Map[String, Json] = {}
  for key in ["range", "severity", "code", "source"]
    case JSON.get(found, key)
      ok(value) -> fields = fields.put(key, value)
      error(_) -> next
    end
  end
  return JSON.object(fields)
end

def expect_error(ctx: BDD.Context, found: Json, name: String) -> BDD.Context
  expected = ERROR_CODES.get(name).unwrap!.to_s
  actual = at(found, ["code"]).unwrap_or(JSON.null()).to_s
  return BDD.assert(ctx, actual == expected, "expected the error #{name} (#{expected}); actual #{found}")
end

def run(ctx: BDD.Context, actions: List[Json]) -> Result[Session]
  dir = folder(ctx)
  none: List[Json] = []
  extra = JSON.list(BDD.get(ctx, "arguments").unwrap_or(JSON.array(none))).unwrap!
  words = extra.map do |word| JSON.string(word).unwrap! end
  ran = session(dir, ["--allow-run", SERVER].concat(words), actions)
  if dir != ""
    _ = Path.remove(dir, TIMEOUT_MS)
  end
  return ran
end

def session(dir: String, arguments: List[String], actions: List[Json]) -> Result[Session]
  server = try Process.spawn_captured("agentica", arguments, ".", TIMEOUT_MS)
  received: List[Json] = []
  for action in actions
    received = received.concat(try perform(server, dir, action))
  end
  try Process.close_stdin(server, TIMEOUT_MS)
  received = received.concat(try read_rest(server))
  exit_code = try Process.wait(server, TIMEOUT_MS)
  output = try Process.output(server, TIMEOUT_MS)
  return ok(Session(messages: received, exit_code: exit_code, stderr: output.stderr))
end

def perform(server: Process, dir: String, action: Json) -> Result[List[Json]]
  kind = try JSON.string(try JSON.get(action, "kind"))
  case kind
    "send" ->
      body = try JSON.string(try JSON.get(action, "body"))
      try Process.send(server, frame(body), TIMEOUT_MS)
      return ok([])
    "await" -> return read_until_diagnostics(server)
    "write" ->
      path = try Path.join([dir, try JSON.string(try JSON.get(action, "name"))])
      try File.write_text(path, try JSON.string(try JSON.get(action, "text")), TIMEOUT_MS)
      return ok([])
    _ -> return error("unknown action #{kind}")
  end
end

def read_until_diagnostics(server: Process) -> Result[List[Json]]
  received: List[Json] = []
  while true
    message = try read_body(server, try Process.read_line(server, TIMEOUT_MS))
    received = received.push(message)
    if at(message, ["method"]).unwrap_or(JSON.null()).to_s == JSON.from(PUBLISH).to_s
      return ok(received)
    end
  end
  return ok(received)
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

def canonical(text: String) -> String
  return JSON.parse(text).unwrap!.to_s
end

def reply(ctx: BDD.Context, id: Int, field: String) -> Result[Json]
  for message in messages(ctx)
    if at(message, ["id"]).unwrap_or(JSON.null()).to_s == id.to_s
      return JSON.get(message, field)
    end
  end
  return error("no reply to request #{id} among #{JSON.array(messages(ctx))}; stderr #{stderr(ctx)}")
end

def at(value: Json, keys: List[String]) -> Result[Json]
  found = value
  for key in keys
    found = try JSON.get(found, key)
  end
  return ok(found)
end

def with_folder(ctx: BDD.Context) -> BDD.Context
  if BDD.get(ctx, "dir").ok?
    return ctx
  end
  base = System.env("TMPDIR").unwrap_or("/tmp")
  path = Path.join([base, "agc-lsp-#{Time.now_ms()}-#{Random.int(0, 999_999_999)}"]).unwrap!
  made = Dir.mkdir_private(path, TIMEOUT_MS)
  if !made.ok?
    return BDD.assert(ctx, false, "cannot make #{path}: #{made.message}")
  end
  return BDD.set(ctx, "dir", JSON.from(Path.real(path).unwrap!))
end

def folder(ctx: BDD.Context) -> String
  return JSON.string(BDD.get(ctx, "dir").unwrap_or(JSON.from(""))).unwrap!
end

def file_path(ctx: BDD.Context, name: String) -> String
  return Path.join([folder(ctx), name]).unwrap!
end

def uri(ctx: BDD.Context, name: String, authority: String = "") -> String
  path = "#{folder(ctx)}/#{name}".replace("%", "%25").replace(" ", "%20")
  return "file://#{authority}#{path}"
end

def messages(ctx: BDD.Context) -> List[Json]
  return JSON.list(BDD.get(ctx, "messages").unwrap!).unwrap!
end

def stderr(ctx: BDD.Context) -> String
  return JSON.string(BDD.get(ctx, "stderr").unwrap_or(JSON.from(""))).unwrap!
end
