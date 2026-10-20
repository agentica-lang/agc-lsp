import BDD from "std/bdd"

SERVER = "src/main.agc"
TIMEOUT_MS = 20000
LOCALHOST = "localhost"
HEX_DIGITS = "0123456789ABCDEF"
ASCII_LIMIT = 128
MANIFEST = "agentica.toml"
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
  arrivals: List[Int]
  sent: Map[String, Json]
  exit_code: Int
  stderr: String
end

struct Heard
  messages: List[Json]
  arrivals: List[Int]
end

def main() -> Void
  BDD.run([
    BDD.step("the language server has started", &started),
    BDD.step("the language server has started with the position encodings {string}", &started_with),
    BDD.step("the language server has started with the arguments {string}", &started_with_arguments),
    BDD.step("the file {string} contains:", &file_contains),
    BDD.step("the files {string} contain:", &files_contain),
    BDD.step("the folder has the link {string} to itself", &links_to_itself),
    BDD.step("the editor opens {string}", &opens),
    BDD.step("the editor opens {string} without waiting", &opens_without_waiting),
    BDD.step("the editor opens the files {string} without waiting", &opens_files_without_waiting),
    BDD.step("the editor opens {string} through a localhost URI", &opens_through_localhost),
    BDD.step("the editor opens an untitled buffer", &opens_untitled),
    BDD.step("the editor saves {string} as:", &saves_as),
    BDD.step("the editor saves {string} without waiting as:", &saves_without_waiting),
    BDD.step("the editor closes {string}", &closes),
    BDD.step("the editor closes {string} without waiting", &closes_without_waiting),
    BDD.step("the editor waits {int} milliseconds", &waits),
    BDD.step("the editor waits for diagnostics", &waits_for_diagnostics),
    BDD.step("the editor waits for the diagnostics of {int} files", &waits_for_files),
    BDD.step("the editor sends {string} before initializing", &sends_request),
    BDD.step("the editor sends the request {string}", &sends_request),
    BDD.step("the editor sends a message that is not JSON", &sends_garbage),
    BDD.step("the editor sends the raw message:", &sends_raw),
    BDD.step("the editor sends a message without a Content-Length header", &sends_unframed),
    BDD.step("the editor exits without shutting down", &exits_early),
    BDD.step("the editor closes the connection", &hangs_up),
    BDD.step("the client runs the session:", &run_session),
    BDD.step("the server answers request {int} with:", &answers_with),
    BDD.step("the server answers {string} within {int} milliseconds", &answers_within),
    BDD.step("the server announces the position encoding {string}", &announces_encoding),
    BDD.step("the server answers {string} with the error {string}", &answers_error),
    BDD.step("the server answers request {int} with the error {string}", &answers_id_error),
    BDD.step("the server does not answer request {int}", &does_not_answer),
    BDD.step("the server reports the error {string}", &reports_error),
    BDD.step("{string} gets these diagnostics:", &gets_diagnostics),
    BDD.step("{string} through a localhost URI gets these diagnostics:", &gets_diagnostics_through_localhost),
    BDD.step("{string} gets no diagnostics", &gets_none),
    BDD.step("{string} gets nothing more", &gets_nothing_more),
    BDD.step("no diagnostics are published", &publishes_nothing),
    BDD.step("the server warns {string}", &warns),
    BDD.step("the diagnostic of {string} has a help line", &has_help),
    BDD.step("the diagnostic of {string} points to {string}", &points_to),
    BDD.step("the diagnostic of {string} points into {string} at {int}:{int}-{int}:{int}", &points_into),
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
  return write_file(with_folder(ctx), args[0])
end

def files_contain(ctx: BDD.Context, args: List[String]) -> BDD.Context
  written = with_folder(ctx)
  for name in names(args[0])
    written = write_file(written, name)
  end
  return written
end

def write_file(ctx: BDD.Context, name: String) -> BDD.Context
  path = file_path(ctx, name)
  parents = Dir.mkdir(parent_of(path), TIMEOUT_MS)
  if !parents.ok?
    return BDD.assert(ctx, false, "cannot make the folder of #{path}: #{parents.message}")
  end
  written = File.write_text(path, BDD.doc_string(ctx), TIMEOUT_MS)
  return BDD.assert(ctx, written.ok?, "cannot write #{path}: #{written.message}")
end

def names(list: String) -> List[String]
  return list.split(",").map do |name| name.strip end
end

def links_to_itself(ctx: BDD.Context, args: List[String]) -> BDD.Context
  ready = with_folder(ctx)
  linked = link(folder(ready), file_path(ready, args[0]))
  return BDD.assert(ready, linked.ok?, "cannot link #{args[0]}: #{linked.message}")
end

def opens(ctx: BDD.Context, args: List[String]) -> BDD.Context
  return awaiting(open_through(ctx, args[0], ""), args[0])
end

def opens_without_waiting(ctx: BDD.Context, args: List[String]) -> BDD.Context
  return open_through(ctx, args[0], "")
end

def opens_files_without_waiting(ctx: BDD.Context, args: List[String]) -> BDD.Context
  opened = ctx
  for name in names(args[0])
    opened = open_through(opened, name, "")
  end
  return opened
end

def opens_through_localhost(ctx: BDD.Context, args: List[String]) -> BDD.Context
  return awaiting(open_through(ctx, args[0], LOCALHOST), args[0])
end

def opens_untitled(ctx: BDD.Context, _args: List[String]) -> BDD.Context
  document = JSON.object({
    "uri": JSON.from("untitled:Untitled-1"),
    "languageId": JSON.from("agentica"),
    "version": JSON.from(1),
    "text": JSON.from("def main() -> Void\n  puts(oops)\nend\n"),
  })
  return notify(ctx, "textDocument/didOpen", JSON.object({"textDocument": document}))
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
  return awaiting(save(ctx, args[0]), args[0])
end

def saves_without_waiting(ctx: BDD.Context, args: List[String]) -> BDD.Context
  return save(ctx, args[0])
end

def save(ctx: BDD.Context, name: String) -> BDD.Context
  ready = with_folder(ctx)
  text = BDD.doc_string(ready)
  document = JSON.object({"uri": JSON.from(uri(ready, name)), "version": JSON.from(2)})
  written = add(ready, JSON.object({
    "kind": JSON.from("write"),
    "name": JSON.from(name),
    "text": JSON.from(text),
  }))
  changed = notify(written, "textDocument/didChange", JSON.object({
    "textDocument": document,
    "contentChanges": JSON.array([JSON.object({"text": JSON.from(text)})]),
  }))
  saved = JSON.object({"uri": JSON.from(uri(ready, name))})
  return notify(changed, "textDocument/didSave", JSON.object({"textDocument": saved}))
end

def closes(ctx: BDD.Context, args: List[String]) -> BDD.Context
  return awaiting(close_document(ctx, args[0]), args[0])
end

def closes_without_waiting(ctx: BDD.Context, args: List[String]) -> BDD.Context
  return close_document(ctx, args[0])
end

def close_document(ctx: BDD.Context, name: String) -> BDD.Context
  document = JSON.object({"uri": JSON.from(uri(ctx, name))})
  return notify(ctx, "textDocument/didClose", JSON.object({"textDocument": document}))
end

def waits(ctx: BDD.Context, args: List[String]) -> BDD.Context
  return add(ctx, JSON.object({"kind": JSON.from("pause"), "ms": JSON.from(args[0].to_i!)}))
end

def waits_for_diagnostics(ctx: BDD.Context, _args: List[String]) -> BDD.Context
  return add(ctx, JSON.object({"kind": JSON.from("await")}))
end

def waits_for_files(ctx: BDD.Context, args: List[String]) -> BDD.Context
  waited = ctx
  for _ in 0...args[0].to_i!
    waited = add(waited, JSON.object({"kind": JSON.from("await")}))
  end
  return waited
end

def awaiting(ctx: BDD.Context, name: String) -> BDD.Context
  if name.ends_with?(".agc")
    return add(ctx, JSON.object({"kind": JSON.from("await")}))
  end
  return ctx
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

def sends_unframed(ctx: BDD.Context, _args: List[String]) -> BDD.Context
  bytes = "Content-Type: application/json\r\n\r\n{}"
  sent = add(ctx, JSON.object({"kind": JSON.from("raw"), "body": JSON.from(bytes)}))
  return BDD.set(sent, "ended", JSON.from(true))
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

def does_not_answer(ctx: BDD.Context, args: List[String]) -> BDD.Context
  return finished(ctx) do |done|
    BDD.assert(done, !reply(done, args[0].to_i!, "id").ok?, "the server answered request #{args[0]}")
  end
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

def gets_nothing_more(ctx: BDD.Context, args: List[String]) -> BDD.Context
  return finished(ctx) do |done| nothing_more(done, uri(done, args[0])) end
end

def answers_within(ctx: BDD.Context, args: List[String]) -> BDD.Context
  return finished(ctx) do |done| answered_within(done, args[0], args[1].to_i!) end
end

def gets_none(ctx: BDD.Context, args: List[String]) -> BDD.Context
  none: List[Json] = []
  return next_publish(ctx, uri(ctx, args[0]), JSON.array(none))
end

def publishes_nothing(ctx: BDD.Context, _args: List[String]) -> BDD.Context
  return finished(ctx) do |done| nothing_published(done) end
end

def warns(ctx: BDD.Context, args: List[String]) -> BDD.Context
  return finished(ctx) do |done|
    BDD.assert(done, stderr(done).contains?(args[0]), "no warning #{args[0].inspect} in #{stderr(done).inspect}")
  end
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

def points_into(ctx: BDD.Context, args: List[String]) -> BDD.Context
  return last_diagnostic(ctx, args[0]) do |done, found|
    expected = JSON.object({
      "uri": JSON.from(uri(done, args[1])),
      "range": JSON.object({
        "start": position("#{args[2]}:#{args[3]}"),
        "end": position("#{args[4]}:#{args[5]}"),
      }),
    })
    related_is(done, found, expected)
  end
end

def exits_with(ctx: BDD.Context, args: List[String]) -> BDD.Context
  return finished(ctx) do |done|
    code = JSON.int(BDD.get(done, "exit").unwrap!).unwrap!
    BDD.assert(done, code == args[0].to_i!, "expected exit code #{args[0]}; actual #{code}; stderr #{stderr(done)}")
  end
end

def related_is(ctx: BDD.Context, found: Json, expected: Json) -> BDD.Context
  none: List[Json] = []
  entries = JSON.list(at(found, ["relatedInformation"]).unwrap_or(JSON.null())).unwrap_or(none)
  if entries.size != 1
    return BDD.assert(ctx, false, "expected one related location in #{found}")
  end
  location = at(entries[0], ["location"]).unwrap_or(JSON.null())
  actual = canonical(JSON.encode(location))
  wanted = canonical(JSON.encode(expected))
  message = JSON.string(at(entries[0], ["message"]).unwrap_or(JSON.null())).unwrap_or("")
  if message == ""
    return BDD.assert(ctx, false, "the related location of #{found} has no message")
  end
  return BDD.assert(ctx, actual == wanted, "expected the location #{wanted}; actual #{actual}")
end

def answered_within(ctx: BDD.Context, method: String, limit: Int) -> BDD.Context
  id = JSON.int(BDD.get(ctx, "request #{method}").unwrap!).unwrap!
  arrivals = JSON.list(BDD.get(ctx, "arrivals").unwrap!).unwrap!
  sent = JSON.int(at(BDD.get(ctx, "sent").unwrap!, [id.to_s]).unwrap!).unwrap!
  index = 0
  for message in messages(ctx)
    if at(message, ["id"]).unwrap_or(JSON.null()).to_s == id.to_s
      waited = JSON.int(arrivals[index]).unwrap! - sent
      return BDD.assert(ctx, waited <= limit, "the answer to #{method} took #{waited} ms; limit #{limit} ms")
    end
    index += 1
  end
  return BDD.assert(ctx, false, "no answer to #{method} among #{JSON.array(messages(ctx))}")
end

def nothing_more(ctx: BDD.Context, target: String) -> BDD.Context
  seen = JSON.int(BDD.get(ctx, "seen #{target}").unwrap_or(JSON.from(0))).unwrap!
  lists = published(ctx, target)
  return BDD.assert(ctx, seen == lists.size, "#{target} got #{lists.size - seen} more publishes: #{lists}")
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
  base = ctx
  if !BDD.get(ctx, "ended").ok?
    base = notify(request(ctx, "shutdown", JSON.null()), "exit", JSON.null())
  end
  actions = JSON.list(BDD.get(base, "script").unwrap_or(JSON.array(none))).unwrap!
  recorded = record(base, run(base, actions))
  if !BDD.get(recorded, "messages").ok?
    return recorded
  end
  return check.call(recorded)
end

def record(ctx: BDD.Context, ran: Result[Session]) -> BDD.Context
  case ran
    ok(done) ->
      with_messages = BDD.set(ctx, "messages", JSON.array(done.messages))
      with_arrivals = BDD.set(with_messages, "arrivals", JSON.array(done.arrivals.map do |ms| JSON.from(ms) end))
      with_sent = BDD.set(with_arrivals, "sent", JSON.object(done.sent))
      with_exit = BDD.set(with_sent, "exit", JSON.from(done.exit_code))
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
  return last_diagnostic(ctx, name) do |done, found|
    check.call(done, JSON.string(at(found, ["message"]).unwrap!).unwrap!)
  end
end

def last_diagnostic(ctx: BDD.Context, name: String, check: Fn[BDD.Context, Json, BDD.Context]) -> BDD.Context
  return finished(ctx) do |done| diagnostic_of(done, name, check) end
end

def nothing_published(ctx: BDD.Context) -> BDD.Context
  for message in messages(ctx)
    if at(message, ["method"]).unwrap_or(JSON.null()).to_s == JSON.from(PUBLISH).to_s
      return BDD.assert(ctx, false, "unexpected publish #{message}")
    end
  end
  return BDD.assert(ctx, true, "")
end

def diagnostic_of(ctx: BDD.Context, name: String, check: Fn[BDD.Context, Json, BDD.Context]) -> BDD.Context
  lists = published(ctx, uri(ctx, name))
  if lists.size == 0 or lists[lists.size - 1].size == 0
    return BDD.assert(ctx, false, "#{name} has no diagnostic")
  end
  return check.call(ctx, lists[lists.size - 1][0])
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
  arrivals: List[Int] = []
  sent: Map[String, Json] = {}
  for action in actions
    sent = noted(sent, action)
    heard = try perform(server, dir, action)
    received = received.concat(heard.messages)
    arrivals = arrivals.concat(heard.arrivals)
  end
  try Process.close_stdin(server, TIMEOUT_MS)
  rest = try read_rest(server)
  exit_code = try Process.wait(server, TIMEOUT_MS)
  output = try Process.output(server, TIMEOUT_MS)
  return ok(Session(
    messages: received.concat(rest.messages),
    arrivals: arrivals.concat(rest.arrivals),
    sent: sent,
    exit_code: exit_code,
    stderr: output.stderr,
  ))
end

def noted(sent: Map[String, Json], action: Json) -> Map[String, Json]
  kind = JSON.string(JSON.get(action, "kind").unwrap_or(JSON.null())).unwrap_or("")
  if kind != "send"
    return sent
  end
  body = JSON.parse(JSON.string(JSON.get(action, "body").unwrap_or(JSON.null())).unwrap_or("")).unwrap_or(JSON.null())
  case JSON.get(body, "id")
    ok(id) -> return sent.put(id.to_s, JSON.from(Time.now_ms()))
    error(_) -> return sent
  end
end

def perform(server: Process, dir: String, action: Json) -> Result[Heard]
  kind = try JSON.string(try JSON.get(action, "kind"))
  case kind
    "send" ->
      body = try JSON.string(try JSON.get(action, "body"))
      try Process.send(server, frame(body), TIMEOUT_MS)
      return ok(nothing_heard())
    "raw" ->
      try Process.send(server, try JSON.string(try JSON.get(action, "body")), TIMEOUT_MS)
      return ok(nothing_heard())
    "await" -> return read_until_diagnostics(server)
    "pause" ->
      Task.sleep(try JSON.int(try JSON.get(action, "ms")))
      return ok(nothing_heard())
    "write" ->
      path = try Path.join([dir, try JSON.string(try JSON.get(action, "name"))])
      try File.write_text(path, try JSON.string(try JSON.get(action, "text")), TIMEOUT_MS)
      return ok(nothing_heard())
    _ -> return error("unknown action #{kind}")
  end
end

def nothing_heard() -> Heard
  return Heard(messages: [], arrivals: [])
end

def read_until_diagnostics(server: Process) -> Result[Heard]
  received: List[Json] = []
  arrivals: List[Int] = []
  while true
    message = try read_body(server, try Process.read_line(server, TIMEOUT_MS))
    received = received.push(message)
    arrivals = arrivals.push(Time.now_ms())
    if at(message, ["method"]).unwrap_or(JSON.null()).to_s == JSON.from(PUBLISH).to_s
      return ok(Heard(messages: received, arrivals: arrivals))
    end
  end
  return ok(Heard(messages: received, arrivals: arrivals))
end

def read_rest(server: Process) -> Result[Heard]
  received: List[Json] = []
  arrivals: List[Int] = []
  while true
    header = Process.read_line(server, TIMEOUT_MS)
    if !header.ok?
      return ok(Heard(messages: received, arrivals: arrivals))
    end
    received = received.push(try read_body(server, header.unwrap!))
    arrivals = arrivals.push(Time.now_ms())
  end
  return ok(Heard(messages: received, arrivals: arrivals))
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

def link(target: String, path: String) -> Result[Void]
  linker = try Process.spawn_captured("ln", ["-s", target, path], ".", TIMEOUT_MS)
  status = try Process.wait(linker, TIMEOUT_MS)
  if status != 0
    return error("ln exited with status #{status}")
  end
  return ok()
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
  real = Path.real(path).unwrap!
  stray = manifest_above(real)
  if stray != ""
    _ = Path.remove(real, TIMEOUT_MS)
    return BDD.assert(ctx, false, "#{stray} exists above the scenario folder #{real}: agentica reads it for every file there; remove it to run the specs")
  end
  return BDD.set(ctx, "dir", JSON.from(real))
end

def manifest_above(path: String) -> String
  parent = parent_of(path)
  while true
    candidate = Path.join([parent, MANIFEST]).unwrap!
    if File.stat(candidate, TIMEOUT_MS).ok?
      return candidate
    end
    if parent == "/"
      return ""
    end
    parent = parent_of(parent)
  end
  return ""
end

def parent_of(path: String) -> String
  parts = path.split("/")
  if parts.size <= 2
    return "/"
  end
  return parts.take(parts.size - 1).join("/")
end

def folder(ctx: BDD.Context) -> String
  return JSON.string(BDD.get(ctx, "dir").unwrap_or(JSON.from(""))).unwrap!
end

def file_path(ctx: BDD.Context, name: String) -> String
  return Path.join([folder(ctx), name]).unwrap!
end

def uri(ctx: BDD.Context, name: String, authority: String = "") -> String
  return "file://#{authority}#{encoded("#{folder(ctx)}/#{name}")}"
end

def encoded(path: String) -> String
  parts: List[String] = []
  for char in path.split("")
    if char == " " or char == "%" or char == "#" or char == "?" or String.code(char) >= ASCII_LIMIT
      for byte in char.to_bytes
        parts = parts.push("%#{HEX_DIGITS.at(byte / 16)}#{HEX_DIGITS.at(byte % 16)}")
      end
    else
      parts = parts.push(char)
    end
  end
  return parts.join("")
end

def messages(ctx: BDD.Context) -> List[Json]
  return JSON.list(BDD.get(ctx, "messages").unwrap!).unwrap!
end

def stderr(ctx: BDD.Context) -> String
  return JSON.string(BDD.get(ctx, "stderr").unwrap_or(JSON.from(""))).unwrap!
end
