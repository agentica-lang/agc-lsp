## Runs the BDD scenarios against the server: its steps drive it through stdio like an editor.

import BDD from "std/bdd"

SERVER = "src/main.agc"
LAUNCHER = "bin/agc-lsp"
TIMEOUT_MS = 20_000
LOCALHOST = "localhost"
HEX_DIGITS = "0123456789ABCDEF"
ASCII_LIMIT = 128
COMMENT_LINE = "# xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
LINES_PER_KB = 10
MANIFEST = "agentica.toml"
RUNS_SUFFIX = ".runs"
PUBLISH = "textDocument/publishDiagnostics"
HOVER = "textDocument/hover"
COMPLETION = "textDocument/completion"
DEFINITION = "textDocument/definition"
SYMBOLS = "textDocument/documentSymbol"
SYMBOL_KINDS = {
  "Function": 12,
  "Struct": 23,
  "Enum": 10,
  "Constant": 14,
  "TypeParameter": 26,
  "Field": 8,
  "EnumMember": 22,
  "Variable": 13,
}
COMPLETION_KINDS = {"Function": 3, "Module": 9}
SEVERITIES = {"error": 1, "warning": 2, "information": 3, "hint": 4}
LOG_TYPES = {"error": 1, "warning": 2, "info": 3, "debug": 4}
LOG_MESSAGE = "window/logMessage"
ERROR_CODES = {
  "parse error": -32_700,
  "invalid request": -32_600,
  "method not found": -32_601,
  "server not initialized": -32_002,
  "request cancelled": -32_800,
}

struct Session
  messages: List[Json]
  arrivals: List[Int]
  sent: Map[String, Json]
  exit_code: Int
  stderr: String
  log: String
  runs: Map[String, Json]
end

struct Entry
  level: String
  text: String
end

struct Heard
  messages: List[Json]
  arrivals: List[Int]
end

def main() -> Void
  BDD.run([
    BDD.step("the language server has started", &started),
    BDD.step("the language server has started through the launcher", &started_through_launcher),
    BDD.step("the language server has started through a link to the launcher", &started_through_link),
    BDD.step(
      "the language server has started through a relative link to the launcher",
      &started_through_relative_link,
    ),
    BDD.step("the language server has started with the position encodings {string}", &started_with),
    BDD.step("the language server has started with the arguments {string}", &started_with_arguments),
    BDD.step("the language server has loaded the builtin catalog", &started_with_catalog),
    BDD.step(
      "the language server has loaded the builtin catalog with the position encodings {string}",
      &started_with_catalog_and_encodings,
    ),
    BDD.step("the editor asks for the log level {string}", &asks_log_level),
    BDD.step("the editor asks for the client log level {string}", &asks_client_log_level),
    BDD.step("the server writes its log to {string}", &writes_log_to),
    BDD.step("the file {string} contains:", &file_contains),
    BDD.step("the files {string} contain:", &files_contain),
    BDD.step("the folder has the link {string} to itself", &links_to_itself),
    BDD.step("the editor opens {string}", &opens),
    BDD.step("the editor opens {string} without waiting", &opens_without_waiting),
    BDD.step("the editor opens {string} with:", &opens_with),
    BDD.step("the editor opens {string} with Windows line endings:", &opens_with_windows_endings),
    BDD.step("the editor opens {string} with a buffer of {int} KB without waiting", &opens_with_large_buffer),
    BDD.step("the editor opens the files {string} without waiting", &opens_files_without_waiting),
    BDD.step("the editor opens {string} through a localhost URI", &opens_through_localhost),
    BDD.step("the editor opens an untitled buffer", &opens_untitled),
    BDD.step("the editor saves {string} as:", &saves_as),
    BDD.step("the editor saves {string} without waiting as:", &saves_without_waiting),
    BDD.step("the editor saves {string} without changes", &saves_without_changes),
    BDD.step("the editor opens {string} without its text", &opens_without_text),
    BDD.step("the editor changes {string} incrementally", &changes_incrementally),
    BDD.step("the editor types in {string}:", &types_in),
    BDD.step("the editor types in {string} without waiting:", &types_in_without_waiting),
    BDD.step("the editor hovers over {string} at {int}:{int}", &hovers),
    BDD.step("the editor asks for completion in {string} at {int}:{int}", &asks_completion),
    BDD.step("the editor hovers over {string} at {int}:{int} without waiting", &hovers_without_waiting),
    BDD.step("the editor hovers over {string} at {int}:{int} three times in a row", &hovers_in_a_row),
    BDD.step("the editor hovers over each of {string} at {int}:{int}", &hovers_over_each),
    BDD.step("the editor hovers over {string} at {int}:{int} and cancels the request", &hovers_and_cancels),
    BDD.step("the editor asks for the definition in {string} at {int}:{int}", &asks_definition),
    BDD.step(
      "the editor asks for the definition in {string} through a localhost URI at {int}:{int}",
      &asks_definition_through_localhost,
    ),
    BDD.step("the editor asks for the symbols of {string}", &asks_symbols),
    BDD.step("the editor closes {string}", &closes),
    BDD.step("the editor closes {string} without waiting", &closes_without_waiting),
    BDD.step("the editor waits {int} milliseconds", &waits),
    BDD.step("the editor waits for diagnostics", &waits_for_diagnostics),
    BDD.step("the editor waits for a log message containing {string}", &waits_for_log),
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
    BDD.step("the server logs a {string} line containing {string}", &logs_line),
    BDD.step("the server logs an {string} line containing {string}", &logs_line),
    BDD.step("the server logs no {string} lines", &logs_no_lines),
    BDD.step("the server logs only JSON lines", &logs_only_json),
    BDD.step("the server never logs {string}", &never_logs),
    BDD.step("the editor gets a {string} log message containing {string}", &gets_log_message),
    BDD.step("the editor gets an {string} log message containing {string}", &gets_log_message),
    BDD.step("the editor gets no log messages", &gets_no_log_messages),
    BDD.step("the editor gets no log message containing {string}", &gets_no_log_message_containing),
    BDD.step("the answer to initialize comes before the log messages", &answers_before_logging),
    BDD.step("the log file {string} has a {string} line containing {string}", &log_file_has_line),
    BDD.step("the log file {string} has an {string} line containing {string}", &log_file_has_line),
    BDD.step("the log file {string} has no {string} lines", &log_file_has_no_lines),
    BDD.step("the log file {string} has only JSON lines", &log_file_only_json),
    BDD.step("the log file {string} never contains {string}", &log_file_never_contains),
    BDD.step("the diagnostic of {string} has a help line", &has_help),
    BDD.step("the diagnostic of {string} points to {string}", &points_to),
    BDD.step("the diagnostic of {string} has no related location", &has_no_related),
    BDD.step("the diagnostic of {string} points into {string} at {int}:{int}-{int}:{int}", &points_into),
    BDD.step("the checker ran {int} time for {string}", &checker_ran),
    BDD.step("the checker ran {int} times for {string}", &checker_ran),
    BDD.step("the hover at {int}:{int} shows {string}", &hover_shows),
    BDD.step("the hover at {int}:{int} shows these builtins:", &hover_shows_these),
    BDD.step("the hover at {int}:{int} shows the type {string}", &hover_shows_type),
    BDD.step("the hover at {int}:{int} shows the declaration {string}", &hover_shows_declaration),
    BDD.step("the hover at {int}:{int} shows the documentation {string}", &hover_shows_documentation),
    BDD.step("the hover at {int}:{int} reads:", &hover_reads),
    BDD.step("the hovers of {string} at {int}:{int} show the type {string}", &hovers_show_type),
    BDD.step("the hover at {int}:{int} is fenced with {int} backticks", &hover_is_fenced),
    BDD.step("the earlier hovers in a row are answered with null", &earlier_hovers_are_null),
    BDD.step("the hover at {int}:{int} is answered as cancelled", &hover_is_cancelled),
    BDD.step("the hover at {int}:{int} is answered before the shutdown", &hover_precedes_shutdown),
    BDD.step("the hover at {int}:{int} does not show {string}", &hover_does_not_show),
    BDD.step("the hover at {int}:{int} covers {int}:{int}-{int}:{int}", &hover_covers),
    BDD.step("there is no hover at {int}:{int}", &no_hover),
    BDD.step("the definition at {int}:{int} is in {string} at {int}:{int}-{int}:{int}", &definition_is),
    BDD.step(
      "the definition at {int}:{int} is in {string} through a localhost URI at {int}:{int}-{int}:{int}",
      &definition_is_through_localhost,
    ),
    BDD.step("there is no definition at {int}:{int}", &no_definition),
    BDD.step("the symbols of {string} are:", &symbols_are),
    BDD.step("there are no symbols for {string}", &no_symbols),
    BDD.step("the symbol {string} of {string} covers {int}:{int}-{int}:{int}", &symbol_covers),
    BDD.step("the completion at {int}:{int} offers:", &completion_offers),
    BDD.step("the completion at {int}:{int} does not offer {string}", &completion_does_not_offer),
    BDD.step("the completion at {int}:{int} offers nothing", &completion_offers_nothing),
    BDD.step("the completion item {string} at {int}:{int} replaces {int}:{int}-{int}:{int}", &completion_replaces),
    BDD.step("the server exits with code {int}", &exits_with),
  ])
end

def started(ctx: BDD.Context, _args: List[String]) -> BDD.Context
  return initialize(ctx, JSON.object({}))
end

def started_through_launcher(ctx: BDD.Context, _args: List[String]) -> BDD.Context
  return initialize(BDD.set(ctx, "launcher", JSON.from(Path.real(LAUNCHER).unwrap!)), JSON.object({}))
end

def started_through_link(ctx: BDD.Context, _args: List[String]) -> BDD.Context
  ready = with_folder(ctx)
  path = file_path(ready, "agc-lsp")
  linked = link(Path.real(LAUNCHER).unwrap!, path)
  if !linked.ok?
    return BDD.assert(ready, false, "cannot link the launcher: #{linked.message}")
  end
  return initialize(BDD.set(ready, "launcher", JSON.from(path)), JSON.object({}))
end

def started_through_relative_link(ctx: BDD.Context, _args: List[String]) -> BDD.Context
  ready = with_folder(ctx)
  first = link(Path.real(LAUNCHER).unwrap!, file_path(ready, "launcher"))
  if !first.ok?
    return BDD.assert(ready, false, "cannot link the launcher: #{first.message}")
  end
  path = file_path(ready, "agc-lsp")
  second = link("launcher", path)
  if !second.ok?
    return BDD.assert(ready, false, "cannot link the launcher: #{second.message}")
  end
  return initialize(BDD.set(ready, "launcher", JSON.from(path)), JSON.object({}))
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

def started_with_catalog(ctx: BDD.Context, _args: List[String]) -> BDD.Context
  return catalog_loaded(initialize(BDD.set(ctx, "asked client log level", JSON.from("info")), JSON.object({})))
end

def started_with_catalog_and_encodings(ctx: BDD.Context, args: List[String]) -> BDD.Context
  asked = BDD.set(ctx, "asked client log level", JSON.from("info"))
  return catalog_loaded(started_with(asked, args))
end

def catalog_loaded(ctx: BDD.Context) -> BDD.Context
  return add(ctx, JSON.object({"kind": JSON.from("log"), "text": JSON.from("loaded the builtin catalog")}))
end

def asks_log_level(ctx: BDD.Context, args: List[String]) -> BDD.Context
  return BDD.set(ctx, "asked log level", JSON.from(args[0]))
end

def asks_client_log_level(ctx: BDD.Context, args: List[String]) -> BDD.Context
  return BDD.set(ctx, "asked client log level", JSON.from(args[0]))
end

def writes_log_to(ctx: BDD.Context, args: List[String]) -> BDD.Context
  return BDD.set(with_folder(ctx), "log file", JSON.from(args[0]))
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

def opens_with(ctx: BDD.Context, args: List[String]) -> BDD.Context
  opened = open_text(with_folder(ctx), args[0], "", BDD.doc_string(ctx))
  return awaiting(opened, args[0])
end

def opens_with_windows_endings(ctx: BDD.Context, args: List[String]) -> BDD.Context
  text = BDD.doc_string(ctx).split("\n").join("\r\n")
  return awaiting(open_text(with_folder(ctx), args[0], "", text), args[0])
end

def opens_with_large_buffer(ctx: BDD.Context, args: List[String]) -> BDD.Context
  lines = (0...args[1].to_i! * LINES_PER_KB).to_a.map do |_| COMMENT_LINE end
  return open_text(with_folder(ctx), args[0], "", "#{lines.join("\n")}\n")
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
  return open_text(ready, name, authority, File.read_text(file_path(ready, name), TIMEOUT_MS).unwrap_or(""))
end

def open_text(ctx: BDD.Context, name: String, authority: String, text: String) -> BDD.Context
  ready = BDD.set(ctx, "open #{name}", JSON.from(true))
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
  if !BDD.get(ready, "open #{name}").ok?
    ready = open_through(ready, name, "")
  end
  text = BDD.doc_string(ready)
  written = add(ready, JSON.object({
    "kind": JSON.from("write"),
    "name": JSON.from(name),
    "text": JSON.from(text),
  }))
  return did_save(change(written, name, text), name)
end

def saves_without_changes(ctx: BDD.Context, args: List[String]) -> BDD.Context
  return awaiting(did_save(with_folder(ctx), args[0]), args[0])
end

def opens_without_text(ctx: BDD.Context, args: List[String]) -> BDD.Context
  ready = with_folder(ctx)
  document = JSON.object({
    "uri": JSON.from(uri(ready, args[0])),
    "languageId": JSON.from("agentica"),
    "version": JSON.from(1),
  })
  return notify(ready, "textDocument/didOpen", JSON.object({"textDocument": document}))
end

def changes_incrementally(ctx: BDD.Context, args: List[String]) -> BDD.Context
  ready = with_folder(ctx)
  document = JSON.object({"uri": JSON.from(uri(ready, args[0])), "version": JSON.from(2)})
  edit = JSON.object({
    "range": JSON.object({"start": position("1:1"), "end": position("1:1")}),
    "text": JSON.from("# "),
  })
  return notify(ready, "textDocument/didChange", JSON.object({
    "textDocument": document,
    "contentChanges": JSON.array([edit]),
  }))
end

def did_save(ctx: BDD.Context, name: String) -> BDD.Context
  saved = JSON.object({"uri": JSON.from(uri(ctx, name))})
  return notify(ctx, "textDocument/didSave", JSON.object({"textDocument": saved}))
end

def types_in(ctx: BDD.Context, args: List[String]) -> BDD.Context
  return awaiting(change(with_folder(ctx), args[0], BDD.doc_string(ctx)), args[0])
end

def types_in_without_waiting(ctx: BDD.Context, args: List[String]) -> BDD.Context
  return change(with_folder(ctx), args[0], BDD.doc_string(ctx))
end

def change(ctx: BDD.Context, name: String, text: String) -> BDD.Context
  document = JSON.object({"uri": JSON.from(uri(ctx, name)), "version": JSON.from(2)})
  return notify(ctx, "textDocument/didChange", JSON.object({
    "textDocument": document,
    "contentChanges": JSON.array([JSON.object({"text": JSON.from(text)})]),
  }))
end

def hovers(ctx: BDD.Context, args: List[String]) -> BDD.Context
  return ask(ctx, "hover", HOVER, args)
end

def asks_completion(ctx: BDD.Context, args: List[String]) -> BDD.Context
  return ask(ctx, "completion", COMPLETION, args)
end

def asks_definition(ctx: BDD.Context, args: List[String]) -> BDD.Context
  return ask(ctx, "definition", DEFINITION, args)
end

def asks_symbols(ctx: BDD.Context, args: List[String]) -> BDD.Context
  ready = with_folder(ctx)
  params = JSON.object({"textDocument": JSON.object({"uri": JSON.from(uri(ready, args[0]))})})
  sent = request(ready, SYMBOLS, params)
  id = BDD.get(sent, "request #{SYMBOLS}").unwrap!
  return wait_for(BDD.set(sent, "symbols #{args[0]}", id), [id])
end

def ask(ctx: BDD.Context, key: String, method: String, args: List[String]) -> BDD.Context
  sent = put_question(ctx, key, method, args, "")
  return wait_for(sent, [BDD.get(sent, "#{key} #{args[1]}:#{args[2]}").unwrap!])
end

def put_question(ctx: BDD.Context, key: String, method: String, args: List[String], authority: String) -> BDD.Context
  ready = with_folder(ctx)
  params = JSON.object({
    "textDocument": JSON.object({"uri": JSON.from(uri(ready, args[0], authority))}),
    "position": position("#{args[1]}:#{args[2]}"),
  })
  sent = request(ready, method, params)
  id = BDD.get(sent, "request #{method}").unwrap!
  return BDD.set(sent, "#{key} #{args[1]}:#{args[2]}", id)
end

def wait_for(ctx: BDD.Context, ids: List[Json]) -> BDD.Context
  return add(ctx, JSON.object({"kind": JSON.from("replies"), "ids": JSON.array(ids)}))
end

def hovers_without_waiting(ctx: BDD.Context, args: List[String]) -> BDD.Context
  return put_question(ctx, "hover", HOVER, args, "")
end

def hovers_in_a_row(ctx: BDD.Context, args: List[String]) -> BDD.Context
  sent = ctx
  ids: List[Json] = []
  for _ in 0...3
    sent = put_question(sent, "hover", HOVER, args, "")
    ids = ids.push(BDD.get(sent, "hover #{args[1]}:#{args[2]}").unwrap!)
  end
  return wait_for(BDD.set(sent, "in a row", JSON.array(ids)), ids)
end

def hovers_over_each(ctx: BDD.Context, args: List[String]) -> BDD.Context
  sent = ctx
  ids: List[Json] = []
  for name in names(args[0])
    sent = put_question(sent, "hover", HOVER, [name, args[1], args[2]], "")
    id = BDD.get(sent, "hover #{args[1]}:#{args[2]}").unwrap!
    sent = BDD.set(sent, "hover #{name} #{args[1]}:#{args[2]}", id)
    ids = ids.push(id)
  end
  return wait_for(sent, ids)
end

def hovers_and_cancels(ctx: BDD.Context, args: List[String]) -> BDD.Context
  sent = put_question(ctx, "hover", HOVER, args, "")
  id = BDD.get(sent, "hover #{args[1]}:#{args[2]}").unwrap!
  cancelled = notify(sent, "$/cancelRequest", JSON.object({"id": id}))
  return wait_for(cancelled, [id])
end

def asks_definition_through_localhost(ctx: BDD.Context, args: List[String]) -> BDD.Context
  sent = put_question(ctx, "definition", DEFINITION, args, LOCALHOST)
  return wait_for(sent, [BDD.get(sent, "definition #{args[1]}:#{args[2]}").unwrap!])
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

def waits_for_log(ctx: BDD.Context, args: List[String]) -> BDD.Context
  return add(ctx, JSON.object({"kind": JSON.from("log"), "text": JSON.from(args[0])}))
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

def logs_line(ctx: BDD.Context, args: List[String]) -> BDD.Context
  return finished(ctx) do |done|
    found = has_line?(entries(stderr(done)), args[0], args[1])
    BDD.assert(done, found, "no #{args[0]} line containing #{args[1].inspect} in #{stderr(done).inspect}")
  end
end

def logs_no_lines(ctx: BDD.Context, args: List[String]) -> BDD.Context
  return finished(ctx) do |done|
    found = has_level?(entries(stderr(done)), args[0])
    BDD.assert(done, !found, "unexpected #{args[0]} lines in #{stderr(done).inspect}")
  end
end

def logs_only_json(ctx: BDD.Context, _args: List[String]) -> BDD.Context
  return finished(ctx) do |done| only_json(done, stderr(done)) end
end

def never_logs(ctx: BDD.Context, args: List[String]) -> BDD.Context
  return finished(ctx) do |done|
    BDD.assert(done, !stderr(done).contains?(args[0]), "#{args[0].inspect} found in #{stderr(done).inspect}")
  end
end

def gets_log_message(ctx: BDD.Context, args: List[String]) -> BDD.Context
  return finished(ctx) do |done|
    found = logged_to_editor?(done, args[0], args[1])
    sent = JSON.array(log_messages(done))
    BDD.assert(done, found, "no #{args[0]} log message containing #{args[1].inspect} in #{sent}")
  end
end

def gets_no_log_messages(ctx: BDD.Context, _args: List[String]) -> BDD.Context
  return finished(ctx) do |done|
    BDD.assert(done, log_messages(done).size == 0, "unexpected log messages #{JSON.array(log_messages(done))}")
  end
end

def gets_no_log_message_containing(ctx: BDD.Context, args: List[String]) -> BDD.Context
  return finished(ctx) do |done|
    found = log_messages(done).filter do |message|
      JSON.string(at(message, ["params", "message"]).unwrap_or(JSON.null())).unwrap_or("").contains?(args[0])
    end
    BDD.assert(done, found.size == 0, "unexpected log messages #{JSON.array(found)}")
  end
end

def answers_before_logging(ctx: BDD.Context, _args: List[String]) -> BDD.Context
  return finished(ctx) do |done| answered_first(done) end
end

def answered_first(ctx: BDD.Context) -> BDD.Context
  first = messages(ctx)[0]
  answer = at(first, ["id"]).unwrap_or(JSON.null()).to_s == "1" and at(first, ["result"]).ok?
  return BDD.assert(ctx, answer, "the first message is not the answer to initialize: #{first}")
end

def log_file_never_contains(ctx: BDD.Context, args: List[String]) -> BDD.Context
  return finished(ctx) do |done|
    BDD.assert(done, !log_text(done).contains?(args[1]), "#{args[1].inspect} found in #{log_text(done).inspect}")
  end
end

def log_file_has_line(ctx: BDD.Context, args: List[String]) -> BDD.Context
  return finished(ctx) do |done|
    found = has_line?(entries(log_text(done)), args[1], args[2])
    BDD.assert(done, found, "no #{args[1]} line containing #{args[2].inspect} in #{log_text(done).inspect}")
  end
end

def log_file_has_no_lines(ctx: BDD.Context, args: List[String]) -> BDD.Context
  return finished(ctx) do |done|
    found = has_level?(entries(log_text(done)), args[1])
    BDD.assert(done, !found, "unexpected #{args[1]} lines in #{log_text(done).inspect}")
  end
end

def log_file_only_json(ctx: BDD.Context, _args: List[String]) -> BDD.Context
  return finished(ctx) do |done| only_json(done, log_text(done)) end
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

def has_no_related(ctx: BDD.Context, args: List[String]) -> BDD.Context
  return last_diagnostic(ctx, args[0]) do |done, found|
    BDD.assert(done, !at(found, ["relatedInformation"]).ok?, "unexpected related location in #{found}")
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

def checker_ran(ctx: BDD.Context, args: List[String]) -> BDD.Context
  return finished(ctx) do |done|
    ran = JSON.int(at(BDD.get(done, "runs").unwrap!, [args[1]]).unwrap_or(JSON.from(0))).unwrap_or(0)
    BDD.assert(done, ran == args[0].to_i!, "the checker ran #{ran} times for #{args[1]}; expected #{args[0]}")
  end
end

def hover_shows(ctx: BDD.Context, args: List[String]) -> BDD.Context
  return finished(ctx) do |done| hover_shown(done, args[0], args[1], [args[2]]) end
end

def hover_shows_these(ctx: BDD.Context, args: List[String]) -> BDD.Context
  names = BDD.table(ctx).drop(1).map do |row| row[0] end
  return finished(ctx) do |done| hover_shown(done, args[0], args[1], names) end
end

def hover_shows_type(ctx: BDD.Context, args: List[String]) -> BDD.Context
  return finished(ctx) do |done| hover_typed(done, args[0], args[1], args[2]) end
end

def hover_shows_declaration(ctx: BDD.Context, args: List[String]) -> BDD.Context
  return finished(ctx) do |done| hover_declared(done, args[0], args[1], args[2]) end
end

def hover_shows_documentation(ctx: BDD.Context, args: List[String]) -> BDD.Context
  return finished(ctx) do |done| hover_documented(done, args[0], args[1], args[2]) end
end

def hover_reads(ctx: BDD.Context, args: List[String]) -> BDD.Context
  expected = BDD.doc_string(ctx)
  return finished(ctx) do |done| hover_read(done, args[0], args[1], expected) end
end

def hovers_show_type(ctx: BDD.Context, args: List[String]) -> BDD.Context
  return finished(ctx) do |done| each_hover_typed(done, args) end
end

def each_hover_typed(ctx: BDD.Context, args: List[String]) -> BDD.Context
  checked = ctx
  for name in names(args[0])
    checked = hover_typed_of(checked, "hover #{name}", args[1], args[2], args[3])
  end
  return checked
end

def earlier_hovers_are_null(ctx: BDD.Context, _args: List[String]) -> BDD.Context
  return finished(ctx) do |done| earlier_are_null(done) end
end

def earlier_are_null(ctx: BDD.Context) -> BDD.Context
  none: List[Json] = []
  ids = JSON.list(BDD.get(ctx, "in a row").unwrap!).unwrap_or(none)
  checked = ctx
  for id in ids.take(ids.size - 1)
    result = reply(checked, JSON.int(id).unwrap!, "result")
    message = "expected null for request #{id}; actual #{result}"
    checked = BDD.assert(checked, result.ok? and result.unwrap!.to_s == "null", message)
  end
  return checked
end

def hover_is_fenced(ctx: BDD.Context, args: List[String]) -> BDD.Context
  return finished(ctx) do |done| hover_fenced(done, args[0], args[1], args[2].to_i!) end
end

def hover_fenced(ctx: BDD.Context, line: String, column: String, width: Int) -> BDD.Context
  case hover_value(ctx, line, column)
    ok(value) ->
      fence = List.repeat("`", width).join("")
      fenced = value.contains?("\n#{fence}agc\n") and value.ends_with?("\n#{fence}") and !value.ends_with?("`#{fence}")
      message = "the hover at #{line}:#{column} is not fenced with #{width} backticks: #{value.inspect}"
      return BDD.assert(ctx, fenced, message)
    error(message) -> return BDD.assert(ctx, false, message)
  end
end

def hover_is_cancelled(ctx: BDD.Context, args: List[String]) -> BDD.Context
  return finished(ctx) do |done|
    id = JSON.int(BDD.get(done, "hover #{args[0]}:#{args[1]}").unwrap!).unwrap!
    id_failed(done, id, "request cancelled")
  end
end

def hover_precedes_shutdown(ctx: BDD.Context, args: List[String]) -> BDD.Context
  return finished(ctx) do |done| answered_before_shutdown(done, "hover #{args[0]}:#{args[1]}") end
end

def answered_before_shutdown(ctx: BDD.Context, key: String) -> BDD.Context
  hover = position_of(ctx, BDD.get(ctx, key).unwrap!.to_s)
  shutdown = position_of(ctx, BDD.get(ctx, "request shutdown").unwrap!.to_s)
  message = "the answer at #{hover} is not before the shutdown at #{shutdown}"
  return BDD.assert(ctx, hover >= 0 and hover < shutdown, message)
end

def position_of(ctx: BDD.Context, id: String) -> Int
  index = 0
  for message in messages(ctx)
    if at(message, ["id"]).unwrap_or(JSON.null()).to_s == id
      return index
    end
    index += 1
  end
  return -1
end

def hover_does_not_show(ctx: BDD.Context, args: List[String]) -> BDD.Context
  return finished(ctx) do |done| hover_lacks(done, args[0], args[1], args[2]) end
end

def hover_covers(ctx: BDD.Context, args: List[String]) -> BDD.Context
  return finished(ctx) do |done| hover_covered(done, args) end
end

def definition_is(ctx: BDD.Context, args: List[String]) -> BDD.Context
  return finished(ctx) do |done| definition_found(done, args) end
end

def no_definition(ctx: BDD.Context, args: List[String]) -> BDD.Context
  return finished(ctx) do |done| definition_absent(done, args[0], args[1]) end
end

def symbols_are(ctx: BDD.Context, args: List[String]) -> BDD.Context
  rows = BDD.table(ctx).drop(1)
  return finished(ctx) do |done| symbols_listed(done, args[0], rows) end
end

def no_symbols(ctx: BDD.Context, args: List[String]) -> BDD.Context
  return finished(ctx) do |done| symbols_absent(done, args[0]) end
end

def symbol_covers(ctx: BDD.Context, args: List[String]) -> BDD.Context
  return finished(ctx) do |done| symbol_covered(done, args) end
end

def no_hover(ctx: BDD.Context, args: List[String]) -> BDD.Context
  return finished(ctx) do |done| hover_absent(done, args[0], args[1]) end
end

def completion_offers(ctx: BDD.Context, args: List[String]) -> BDD.Context
  rows = BDD.table(ctx).drop(1)
  return finished(ctx) do |done| completion_offered(done, args[0], args[1], rows) end
end

def completion_does_not_offer(ctx: BDD.Context, args: List[String]) -> BDD.Context
  return finished(ctx) do |done| completion_lacks(done, args[0], args[1], args[2]) end
end

def completion_offers_nothing(ctx: BDD.Context, args: List[String]) -> BDD.Context
  return finished(ctx) do |done| completion_empty(done, args[0], args[1]) end
end

def completion_replaces(ctx: BDD.Context, args: List[String]) -> BDD.Context
  return finished(ctx) do |done| completion_replaced(done, args) end
end

def exits_with(ctx: BDD.Context, args: List[String]) -> BDD.Context
  return finished(ctx) do |done|
    code = JSON.int(BDD.get(done, "exit").unwrap!).unwrap!
    BDD.assert(done, code == args[0].to_i!, "expected exit code #{args[0]}; actual #{code}; stderr #{stderr(done)}")
  end
end

def result_at(ctx: BDD.Context, key: String, line: String, column: String) -> Result[Json]
  id = try JSON.int(try BDD.get(ctx, "#{key} #{line}:#{column}"))
  return reply(ctx, id, "result")
end

def hover_shown(ctx: BDD.Context, line: String, column: String, names: List[String]) -> BDD.Context
  case result_at(ctx, "hover", line, column)
    ok(result) ->
      contents = at(result, ["contents"]).unwrap_or(JSON.null())
      kind = JSON.string(at(contents, ["kind"]).unwrap_or(JSON.null())).unwrap_or("")
      value = JSON.string(at(contents, ["value"]).unwrap_or(JSON.null())).unwrap_or("")
      missing = names.filter do |name| !value.contains?("```agc\n#{name}(") end
      shown = kind == "markdown" and missing.size == 0
      return BDD.assert(ctx, shown, "the hover at #{line}:#{column} lacks #{missing.join(", ")} in #{result}")
    error(message) -> return BDD.assert(ctx, false, message)
  end
end

def hover_value(ctx: BDD.Context, line: String, column: String) -> Result[String]
  return hover_value_of(ctx, "hover", line, column)
end

def hover_value_of(ctx: BDD.Context, key: String, line: String, column: String) -> Result[String]
  result = try result_at(ctx, key, line, column)
  if result.to_s == "null"
    return error("no hover at #{line}:#{column}")
  end
  return JSON.string(at(result, ["contents", "value"]).unwrap_or(JSON.null()))
end

def hover_typed(ctx: BDD.Context, line: String, column: String, type: String) -> BDD.Context
  return hover_typed_of(ctx, "hover", line, column, type)
end

def hover_typed_of(ctx: BDD.Context, key: String, line: String, column: String, type: String) -> BDD.Context
  case hover_value_of(ctx, key, line, column)
    ok(value) ->
      shown = value.contains?(": #{type}\n```")
      message = "the hover at #{line}:#{column} does not show the type #{type} in #{value.inspect}"
      return BDD.assert(ctx, shown, message)
    error(message) -> return BDD.assert(ctx, false, message)
  end
end

def hover_declared(ctx: BDD.Context, line: String, column: String, signature: String) -> BDD.Context
  case hover_value(ctx, line, column)
    ok(value) ->
      shown = value.starts_with?("```agc\n#{signature}\n```\n")
      message = "the hover at #{line}:#{column} does not start with the declaration #{signature} in #{value.inspect}"
      return BDD.assert(ctx, shown, message)
    error(message) -> return BDD.assert(ctx, false, message)
  end
end

def hover_documented(ctx: BDD.Context, line: String, column: String, doc: String) -> BDD.Context
  case hover_value(ctx, line, column)
    ok(value) ->
      shown = value.contains?("\n\n#{doc}\n\n")
      message = "the hover at #{line}:#{column} does not show the documentation #{doc} in #{value.inspect}"
      return BDD.assert(ctx, shown, message)
    error(message) -> return BDD.assert(ctx, false, message)
  end
end

def hover_read(ctx: BDD.Context, line: String, column: String, expected: String) -> BDD.Context
  case hover_value(ctx, line, column)
    ok(value) ->
      message = "the hover at #{line}:#{column} reads #{value.inspect}; expected #{expected.inspect}"
      return BDD.assert(ctx, value == expected, message)
    error(message) -> return BDD.assert(ctx, false, message)
  end
end

def hover_lacks(ctx: BDD.Context, line: String, column: String, name: String) -> BDD.Context
  case hover_value(ctx, line, column)
    ok(value) ->
      found = value.contains?("```agc\n#{name}(")
      return BDD.assert(ctx, !found, "the hover at #{line}:#{column} shows #{name} in #{value.inspect}")
    error(message) -> return BDD.assert(ctx, false, message)
  end
end

def definition_is_through_localhost(ctx: BDD.Context, args: List[String]) -> BDD.Context
  return finished(ctx) do |done| located_at(done, args, LOCALHOST) end
end

def definition_found(ctx: BDD.Context, args: List[String]) -> BDD.Context
  return located_at(ctx, args, "")
end

def located_at(ctx: BDD.Context, args: List[String], authority: String) -> BDD.Context
  case result_at(ctx, "definition", args[0], args[1])
    ok(result) ->
      start = position("#{args[3]}:#{args[4]}")
      stop = position("#{args[5]}:#{args[6]}")
      range = JSON.object({"start": start, "end": stop})
      wanted = canonical(JSON.encode(JSON.object({"uri": JSON.from(uri(ctx, args[2], authority)), "range": range})))
      actual = canonical(JSON.encode(result))
      return BDD.assert(ctx, actual == wanted, "expected the location #{wanted}; actual #{actual}")
    error(message) -> return BDD.assert(ctx, false, message)
  end
end

def definition_absent(ctx: BDD.Context, line: String, column: String) -> BDD.Context
  case result_at(ctx, "definition", line, column)
    ok(result) ->
      return BDD.assert(ctx, result.to_s == "null", "expected no definition at #{line}:#{column}; actual #{result}")
    error(message) -> return BDD.assert(ctx, false, message)
  end
end

def symbols_listed(ctx: BDD.Context, name: String, rows: List[List[String]]) -> BDD.Context
  id = JSON.int(BDD.get(ctx, "symbols #{name}").unwrap!).unwrap!
  case reply(ctx, id, "result")
    ok(result) ->
      none: List[Json] = []
      top = JSON.list(result).unwrap_or(none)
      listed = flattened(top, "")
      actual = JSON.encode(listed.map do |row| row.take(3) end)
      wanted = JSON.encode(rows.map do |row| row.take(3) end)
      misplaced = listed.filter do |row| row[3] != "" end
      checked = BDD.assert(ctx, misplaced.size == 0, "a name is outside its range: #{misplaced}")
      return BDD.assert(checked, actual == wanted, "expected the symbols #{wanted}; actual #{actual}")
    error(message) -> return BDD.assert(ctx, false, message)
  end
end

def symbol_covered(ctx: BDD.Context, args: List[String]) -> BDD.Context
  id = JSON.int(BDD.get(ctx, "symbols #{args[1]}").unwrap!).unwrap!
  case reply(ctx, id, "result")
    ok(result) ->
      none: List[Json] = []
      found = JSON.list(result).unwrap_or(none).filter do |symbol|
        JSON.string(at(symbol, ["name"]).unwrap_or(JSON.null())).unwrap_or("") == args[0]
      end
      if found.size == 0
        return BDD.assert(ctx, false, "no symbol #{args[0]} in #{result}")
      end
      actual = span_text(at(found[0], ["range"]).unwrap_or(JSON.null()))
      wanted = "#{args[2]}:#{args[3]}-#{args[4]}:#{args[5]}"
      return BDD.assert(ctx, actual == wanted, "expected the range #{wanted}; actual #{actual}")
    error(message) -> return BDD.assert(ctx, false, message)
  end
end

def symbols_absent(ctx: BDD.Context, name: String) -> BDD.Context
  id = JSON.int(BDD.get(ctx, "symbols #{name}").unwrap!).unwrap!
  case reply(ctx, id, "result")
    ok(result) -> return BDD.assert(ctx, result.to_s == "null", "expected no symbols; actual #{result}")
    error(message) -> return BDD.assert(ctx, false, message)
  end
end

def flattened(symbols: List[Json], parent: String) -> List[List[String]]
  rows: List[List[String]] = []
  for symbol in symbols
    name = JSON.string(at(symbol, ["name"]).unwrap_or(JSON.null())).unwrap_or("")
    qualified = name
    if parent != ""
      qualified = "#{parent}.#{name}"
    end
    kind = JSON.int(at(symbol, ["kind"]).unwrap_or(JSON.null())).unwrap_or(0)
    selection = at(symbol, ["selectionRange"]).unwrap_or(JSON.null())
    outside = ""
    if !inside?(at(symbol, ["range"]).unwrap_or(JSON.null()), selection)
      outside = "outside"
    end
    rows = rows.push([qualified, kind_name(kind), span_text(selection), outside])
    none: List[Json] = []
    children = JSON.list(at(symbol, ["children"]).unwrap_or(JSON.null())).unwrap_or(none)
    rows = rows.concat(flattened(children, qualified))
  end
  return rows
end

def kind_name(kind: Int) -> String
  for name in SYMBOL_KINDS.keys
    if SYMBOL_KINDS.get(name).unwrap_or(0) == kind
      return name
    end
  end
  return kind.to_s
end

def span_text(range: Json) -> String
  return "#{edge_text(range, "start")}-#{edge_text(range, "end")}"
end

def edge_text(range: Json, edge: String) -> String
  line = JSON.int(at(range, [edge, "line"]).unwrap_or(JSON.null())).unwrap_or(-1)
  character = JSON.int(at(range, [edge, "character"]).unwrap_or(JSON.null())).unwrap_or(-1)
  return "#{line + 1}:#{character + 1}"
end

def inside?(outer: Json, inner: Json) -> Bool
  return (
    edge_value(outer, "start") <= edge_value(inner, "start") and
    edge_value(inner, "end") <= edge_value(outer, "end")
  )
end

def edge_value(range: Json, edge: String) -> Int
  line = JSON.int(at(range, [edge, "line"]).unwrap_or(JSON.null())).unwrap_or(-1)
  character = JSON.int(at(range, [edge, "character"]).unwrap_or(JSON.null())).unwrap_or(-1)
  return line * 1_000_000 + character
end

def hover_absent(ctx: BDD.Context, line: String, column: String) -> BDD.Context
  case result_at(ctx, "hover", line, column)
    ok(result) ->
      return BDD.assert(ctx, result.to_s == "null", "expected no hover at #{line}:#{column}; actual #{result}")
    error(message) -> return BDD.assert(ctx, false, message)
  end
end

def hover_covered(ctx: BDD.Context, args: List[String]) -> BDD.Context
  case result_at(ctx, "hover", args[0], args[1])
    ok(result) ->
      start = position("#{args[2]}:#{args[3]}")
      stop = position("#{args[4]}:#{args[5]}")
      wanted = canonical(JSON.encode(JSON.object({"start": start, "end": stop})))
      actual = canonical(JSON.encode(at(result, ["range"]).unwrap_or(JSON.null())))
      return BDD.assert(ctx, actual == wanted, "expected the range #{wanted}; actual #{actual}")
    error(message) -> return BDD.assert(ctx, false, message)
  end
end

def completion_offered(ctx: BDD.Context, line: String, column: String, rows: List[List[String]]) -> BDD.Context
  case result_at(ctx, "completion", line, column)
    ok(result) ->
      none: List[Json] = []
      items = JSON.list(result).unwrap_or(none)
      missing = rows.filter do |row| !offers?(items, row) end
      return BDD.assert(ctx, missing.size == 0, "the completion at #{line}:#{column} lacks #{missing} in #{result}")
    error(message) -> return BDD.assert(ctx, false, message)
  end
end

def completion_replaced(ctx: BDD.Context, args: List[String]) -> BDD.Context
  case result_at(ctx, "completion", args[1], args[2])
    ok(result) ->
      none: List[Json] = []
      items = JSON.list(result).unwrap_or(none).filter do |item|
        JSON.string(at(item, ["label"]).unwrap_or(JSON.null())).unwrap_or("") == args[0]
      end
      if items.size == 0
        return BDD.assert(ctx, false, "the completion at #{args[1]}:#{args[2]} lacks #{args[0]}")
      end
      edit = at(items[0], ["textEdit"]).unwrap_or(JSON.null())
      start = position("#{args[3]}:#{args[4]}")
      stop = position("#{args[5]}:#{args[6]}")
      range = JSON.object({"start": start, "end": stop})
      wanted = canonical(JSON.encode(JSON.object({"range": range, "newText": JSON.from(args[0])})))
      actual = canonical(JSON.encode(edit))
      return BDD.assert(ctx, actual == wanted, "expected the edit #{wanted}; actual #{actual}")
    error(message) -> return BDD.assert(ctx, false, message)
  end
end

def completion_lacks(ctx: BDD.Context, line: String, column: String, label: String) -> BDD.Context
  case result_at(ctx, "completion", line, column)
    ok(result) ->
      found = labels(result).filter do |offered| offered == label end
      return BDD.assert(ctx, found.size == 0, "the completion at #{line}:#{column} offers #{label}")
    error(message) -> return BDD.assert(ctx, false, message)
  end
end

def completion_empty(ctx: BDD.Context, line: String, column: String) -> BDD.Context
  case result_at(ctx, "completion", line, column)
    ok(result) ->
      empty = JSON.list(result).ok? and labels(result).size == 0
      return BDD.assert(ctx, empty, "expected an empty list at #{line}:#{column}; actual #{result}")
    error(message) -> return BDD.assert(ctx, false, message)
  end
end

def offers?(items: List[Json], row: List[String]) -> Bool
  return items.filter do |item| item_matches?(item, row) end.size > 0
end

def item_matches?(item: Json, row: List[String]) -> Bool
  label = JSON.string(at(item, ["label"]).unwrap_or(JSON.null())).unwrap_or("")
  kind = JSON.int(at(item, ["kind"]).unwrap_or(JSON.null())).unwrap_or(0)
  detail = JSON.string(at(item, ["detail"]).unwrap_or(JSON.null())).unwrap_or("")
  documentation = JSON.string(at(item, ["documentation", "value"]).unwrap_or(JSON.null())).unwrap_or("")
  if label != row[0] or kind != COMPLETION_KINDS.get(row[1]).unwrap!
    return false
  end
  return row[2] == "" or (detail.starts_with?("#{row[2]}(") and documentation.length > 0)
end

def labels(result: Json) -> List[String]
  none: List[Json] = []
  return JSON.list(result).unwrap_or(none).map do |item|
    JSON.string(at(item, ["label"]).unwrap_or(JSON.null())).unwrap_or("")
  end
end

def entries(text: String) -> List[Entry]
  found: List[Entry] = []
  for line in text.split("\n")
    case entry_of(line)
      ok(entry) -> found = found.push(entry)
      error(_) -> next
    end
  end
  return found
end

def entry_of(line: String) -> Result[Entry]
  if line.starts_with?("{")
    parsed = try JSON.parse(line)
    level = try JSON.string(try JSON.get(parsed, "level"))
    return ok(Entry(level: level, text: line))
  end
  words = line.split(" ")
  if words.size < 3 or !LOG_TYPES.get(words[1].downcase).ok?
    return error("not a log line")
  end
  return ok(Entry(level: words[1].downcase, text: line))
end

def has_line?(found: List[Entry], level: String, text: String) -> Bool
  return found.filter do |entry| entry.level == level and entry.text.contains?(text) end.size > 0
end

def has_level?(found: List[Entry], level: String) -> Bool
  return found.filter do |entry| entry.level == level end.size > 0
end

def only_json(ctx: BDD.Context, text: String) -> BDD.Context
  lines = text.split("\n").filter do |line| line.strip.length > 0 end
  for line in lines
    if !JSON.parse(line).ok?
      return BDD.assert(ctx, false, "not a JSON line: #{line.inspect}")
    end
  end
  return BDD.assert(ctx, lines.size > 0, "no lines in #{text.inspect}")
end

def log_messages(ctx: BDD.Context) -> List[Json]
  return messages(ctx).filter do |message|
    at(message, ["method"]).unwrap_or(JSON.null()).to_s == JSON.from(LOG_MESSAGE).to_s
  end
end

def logged_to_editor?(ctx: BDD.Context, level: String, text: String) -> Bool
  wanted = LOG_TYPES.get(level).unwrap!
  matching = log_messages(ctx).filter do |message|
    kind = JSON.int(at(message, ["params", "type"]).unwrap_or(JSON.null())).unwrap_or(0)
    shown = JSON.string(at(message, ["params", "message"]).unwrap_or(JSON.null())).unwrap_or("")
    kind == wanted and shown.contains?(text)
  end
  return matching.size > 0
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
    case at(message, ["error"])
      ok(found) ->
        if at(message, ["id"]).unwrap_or(JSON.from(0)).to_s == "null"
          return expect_error(ctx, found, name)
        end
      error(_) -> next
    end
  end
  return BDD.assert(ctx, false, "no error without an id among #{JSON.array(messages(ctx))}")
end

def initialize(ctx: BDD.Context, capabilities: Json) -> BDD.Context
  params: Map[String, Json] = {"capabilities": capabilities}
  options: Map[String, Json] = {}
  for pair in [["asked log level", "logLevel"], ["asked client log level", "clientLogLevel"]]
    case BDD.get(ctx, pair[0])
      ok(level) -> options = options.put(pair[1], level)
      error(_) -> next
    end
  end
  if options.size > 0
    params = params.put("initializationOptions", JSON.object(options))
  end
  return request(ctx, "initialize", JSON.object(params))
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
      with_stderr = BDD.set(with_exit, "stderr", JSON.from(done.stderr))
      with_log = BDD.set(with_stderr, "log", JSON.from(done.log))
      return BDD.set(with_log, "runs", JSON.object(done.runs))
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
  log_path = ""
  log_file = JSON.string(BDD.get(ctx, "log file").unwrap_or(JSON.from(""))).unwrap_or("")
  if log_file != ""
    log_path = file_path(ctx, log_file)
    words = words.concat(["--log-file", log_path])
  end
  command = "agentica"
  arguments = ["--allow-run", SERVER].concat(words)
  launcher = JSON.string(BDD.get(ctx, "launcher").unwrap_or(JSON.from(""))).unwrap_or("")
  if launcher != ""
    command = launcher
    arguments = words
  end
  ran = session(dir, command, arguments, actions)
  counts = runs_in(dir)
  log = ""
  if log_path != ""
    log = File.read_text(log_path, TIMEOUT_MS).unwrap_or("")
  end
  if dir != ""
    _ = Path.remove(dir, TIMEOUT_MS)
  end
  case ran
    ok(done) -> return ok(done.with(log: log, runs: counts))
    error(message) -> return error(message)
  end
end

def runs_in(dir: String) -> Map[String, Json]
  counts: Map[String, Json] = {}
  none: List[String] = []
  for entry in Dir.list(dir, TIMEOUT_MS).unwrap_or(none)
    if entry.ends_with?(RUNS_SUFFIX)
      lines = File.read_text(Path.join([dir, entry]).unwrap!, TIMEOUT_MS).unwrap_or("").split("\n")
      name = entry.slice(0, entry.length - RUNS_SUFFIX.length)
      written = lines.filter do |line| line.strip.length > 0 end.size
      counts = counts.put(name, JSON.from(written))
    end
  end
  return counts
end

def session(dir: String, command: String, arguments: List[String], actions: List[Json]) -> Result[Session]
  server = try Process.spawn_captured(command, arguments, ".", TIMEOUT_MS)
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
    log: "",
    runs: {},
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
    "replies" -> return read_until_replies(server, try JSON.list(try JSON.get(action, "ids")))
    "log" -> return read_until_log(server, try JSON.string(try JSON.get(action, "text")))
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

def read_until_replies(server: Process, ids: List[Json]) -> Result[Heard]
  received: List[Json] = []
  arrivals: List[Int] = []
  waiting = ids.map do |id| id.to_s end
  while waiting.size > 0
    message = try read_body(server, try Process.read_line(server, TIMEOUT_MS))
    received = received.push(message)
    arrivals = arrivals.push(Time.now_ms())
    answered = at(message, ["result"]).ok? or at(message, ["error"]).ok?
    sender = at(message, ["id"]).unwrap_or(JSON.null()).to_s
    if answered
      waiting = waiting.filter do |id| id != sender end
    end
  end
  return ok(Heard(messages: received, arrivals: arrivals))
end

def read_until_log(server: Process, text: String) -> Result[Heard]
  received: List[Json] = []
  arrivals: List[Int] = []
  while true
    message = try read_body(server, try Process.read_line(server, TIMEOUT_MS))
    received = received.push(message)
    arrivals = arrivals.push(Time.now_ms())
    shown = JSON.string(at(message, ["params", "message"]).unwrap_or(JSON.null())).unwrap_or("")
    if at(message, ["method"]).unwrap_or(JSON.null()).to_s == JSON.from(LOG_MESSAGE).to_s and shown.contains?(text)
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
    message = (
      "#{stray} exists above the scenario folder #{real}: " +
      "agentica reads it for every file there; remove it to run the specs"
    )
    return BDD.assert(ctx, false, message)
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

def log_text(ctx: BDD.Context) -> String
  return JSON.string(BDD.get(ctx, "log").unwrap_or(JSON.from(""))).unwrap!
end

def stderr(ctx: BDD.Context) -> String
  return JSON.string(BDD.get(ctx, "stderr").unwrap_or(JSON.from(""))).unwrap!
end
