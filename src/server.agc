## Runs the lifecycle of the server and dispatches its requests and notifications.

import Asks from "asks"
import Catalog from "catalog"
import Check from "check"
import Completion from "completion"
import Cursor from "cursor"
import {UTF16, UTF32} from "columns"
import Events from "events"
import Fields from "fields"
import Hover from "hover"
import Logs from "logs"
import Lookup from "lookup"
import Options from "options"
import Rpc from "rpc"
import Schedule from "schedule"
import Analysis from "std/analysis"
import Logger from "std/logger"
import Uri from "uri"
import Words from "words"
import Workspace from "workspace"

PARSE_ERROR = -32_700
INVALID_REQUEST = -32_600
REQUEST_CANCELLED = -32_800
METHOD_NOT_FOUND = -32_601
SERVER_NOT_INITIALIZED = -32_002
FULL_SYNC = 1
AGENTICA_EXTENSION = ".agc"
EVENT_CAPACITY = 256
WAIT_MS = 1000
READER_CHECK_MS = 1
CHANGE_DELAY_MS = 200

## Holds the state of the server: its options, the open documents and the session that holds their text, the plan of
## the checks and the catalog.
export struct State
  ## Holds the command-line options.
  options: Options.Options
  ## Is the position encoding that the session uses.
  encoding: String
  ## Is true once initialize was answered.
  initialized: Bool
  ## Is true once shutdown was requested.
  shut_down: Bool
  ## Is the channel of the events of the server loop.
  events: Channel[Events.Event]
  ## Is the plan of the checks.
  plan: Schedule.Plan
  ## Maps each URI to the file that its diagnostic points into.
  pointing: Map[String, String]
  ## Maps the path of each open document to its text.
  documents: Map[String, String]
  ## Is the session of std/analysis with the text of every open document and the checks refreshed into its cache.
  session: Analysis.Session
  ## Counts the changes to the open documents that the session holds.
  revision: Int
  ## Is the working folder, from which std/analysis writes the names of files below it.
  folder: String
  ## Is the catalog of builtins, empty until it loads.
  catalog: Catalog.Book
  ## Lists the catalog tasks that have not ended.
  loaders: List[Task[Result[Void]]]
  ## Is the plan of the queries that answer definition, references, hover, document symbol and workspace symbol
  ## requests.
  asks: Asks.Plan
  ## Is the absolute path of the workspace folder, empty when the editor gave none.
  root: String
end

enum Next
  Continue(State)
  Exit(Int)
end

## Returns the state of a server that has not been initialized.
export def start(options: Options.Options) -> State
  events: Channel[Events.Event] = Channel.new(EVENT_CAPACITY)
  pointing: Map[String, String] = {}
  documents: Map[String, String] = {}
  loaders: List[Task[Result[Void]]] = []
  return State(
    options: options,
    encoding: UTF16,
    initialized: false,
    shut_down: false,
    events: events,
    plan: Schedule.start(events),
    pointing: pointing,
    documents: documents,
    session: Analysis.open(Analysis.workspace()),
    revision: 0,
    folder: Uri.trimmed(Path.cwd().unwrap_or("/")),
    catalog: Catalog.empty(),
    loaders: loaders,
    asks: Asks.start(),
    root: "",
  )
end

## Runs the server loop until the editor exits or the input ends, and returns the exit status.
export def serve(state: State) -> Int
  reader = Task.spawn(&Events.read_input, state.events)
  current = state
  while true
    case current.events.recv(Schedule.wait_ms(current.plan, WAIT_MS))
      ok(event) ->
        case dispatch(current, event)
          Next.Continue(next) -> current = watch(next.with(plan: Schedule.tick(next.plan, basis(next))))
          Next.Exit(status) -> return finish(current, reader, status)
        end
      error(_) ->
        if reader_crashed?(reader)
          Logger.err("the reader of the input crashed")
          return finish(current, reader, 1)
        end
        current = watch(current.with(plan: Schedule.tick(current.plan, basis(current))))
    end
  end
  return finish(current, reader, exit_status(current))
end

def basis(state: State) -> Schedule.Basis
  return Schedule.Basis(session: state.session, revision: state.revision)
end

def reader_crashed?(reader: Task[Result[Void]]) -> Bool
  case Task.await(reader, READER_CHECK_MS)
    Await.Done(outcome) -> return !outcome.ok?
    Await.TimedOut -> return false
  end
end

def watch(state: State) -> State
  if state.loaders.size == 0 and state.asks.running.size == 0
    return state
  end
  return dropped_answer(state.with(loaders: running(state.loaders)), Asks.reap(state.asks))
end

def running(loaders: List[Task[Result[Void]]]) -> List[Task[Result[Void]]]
  alive: List[Task[Result[Void]]] = []
  for loader in loaders
    case Task.await(loader, READER_CHECK_MS)
      Await.Done(outcome) ->
        if !outcome.ok?
          Logger.err("the builtin catalog task crashed: #{outcome.message}")
        end
      Await.TimedOut -> alive = alive.push(loader)
    end
  end
  return alive
end

def dropped_answer(state: State, change: Asks.Change) -> State
  for id in change.dropped
    Rpc.respond(id, JSON.null())
  end
  return state.with(asks: change.plan)
end

def finish(state: State, reader: Task[Result[Void]], status: Int) -> Int
  Task.cancel(reader)
  for loader in state.loaders
    Task.cancel(loader)
  end
  Asks.stop(state.asks)
  Schedule.stop(state.plan)
  return status
end

def dispatch(state: State, event: Events.Event) -> Next
  case event
    Events.Event.Checked(report) -> return Next.Continue(checked(state, report))
    Events.Event.Answered(answer) ->
      case Asks.settle(state.asks, answer.id)
        ok(plan) ->
          Rpc.respond(answer.id, answer.result)
          return Next.Continue(state.with(asks: plan))
        error(_) -> return Next.Continue(state)
      end
    Events.Event.Cataloged(outcome) ->
      case outcome
        ok(book) -> return Next.Continue(state.with(catalog: book))
        error(_) -> return Next.Continue(state)
      end
    Events.Event.Input(incoming) -> return input(state, incoming)
    Events.Event.Log(logged) ->
      Logs.write_to_editor(logged)
      return Next.Continue(state)
  end
end

def input(state: State, incoming: Rpc.Incoming) -> Next
  case incoming
    Rpc.Incoming.End -> return Next.Exit(exit_status(state))
    Rpc.Incoming.Malformed(message) ->
      Rpc.fail(JSON.null(), PARSE_ERROR, message)
      return Next.Continue(state)
    Rpc.Incoming.Unframed(message) ->
      Logger.err("#{message}; the stream cannot be read further")
      return Next.Exit(1)
    Rpc.Incoming.Message(message) -> return handle(state, message)
  end
end

def checked(state: State, report: Events.Report) -> State
  if state.shut_down
    return state
  end
  held = adopted(state, report)
  if !Schedule.current?(held.plan, report)
    return held
  end
  return published(held.with(plan: Schedule.settle(held.plan, report.uri)), report)
end

def adopted(state: State, report: Events.Report) -> State
  if report.revision != state.revision
    return state
  end
  return state.with(session: report.session)
end

def published(state: State, report: Events.Report) -> State
  path = Uri.path_of(report.uri).unwrap_or("")
  placing = Check.Placing(path: path, documents: state.documents, folder: state.folder, encoding: state.encoding)
  found = Check.diagnostics(report.checked, placing)
  publish(report.uri, found)
  return state.with(pointing: point(state.pointing, report.uri, Check.points_into(found)))
end

def point(pointing: Map[String, String], uri: String, target: String) -> Map[String, String]
  case Uri.path_of(target)
    ok(path) -> return pointing.put(uri, path)
    error(_) -> return pointing.delete(uri)
  end
end

def handle(state: State, message: Json) -> Next
  if !object?(message)
    Rpc.fail(JSON.null(), INVALID_REQUEST, "a message must be a JSON object")
    return Next.Continue(state)
  end
  method = JSON.string(JSON.get(message, "method").unwrap_or(JSON.null())).unwrap_or("")
  log_received(message, method)
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
    "textDocument/hover" -> return hover(state, id, params)
    "textDocument/definition" -> return definition(state, id, params)
    "textDocument/documentSymbol" -> return symbols(state, id, params)
    "textDocument/references" -> return references(state, id, params)
    "workspace/symbol" -> return workspace_symbols(state, id, params)
    "textDocument/completion" ->
      Rpc.respond(id, completion(state, params))
      return state
    "shutdown" ->
      Logger.info("shutting down")
      released = dropped_answer(state, Asks.abandon(state.asks))
      Rpc.respond(id, JSON.null())
      return released.with(plan: Schedule.stop(state.plan), shut_down: true)
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
  encoding = UTF16
  if Set.new(offered(params)).include?(UTF32)
    encoding = UTF32
  end
  sync = JSON.object({
    "openClose": JSON.from(true),
    "change": JSON.from(FULL_SYNC),
    "save": JSON.object({"includeText": JSON.from(false)}),
  })
  capabilities = JSON.object({
    "positionEncoding": JSON.from(encoding),
    "textDocumentSync": sync,
    "hoverProvider": JSON.from(true),
    "definitionProvider": JSON.from(true),
    "documentSymbolProvider": JSON.from(true),
    "referencesProvider": JSON.from(true),
    "workspaceSymbolProvider": JSON.from(true),
    "completionProvider": JSON.object({"triggerCharacters": JSON.array([JSON.from(".")])}),
  })
  Rpc.respond(id, JSON.object({
    "capabilities": capabilities,
    "serverInfo": JSON.object({"name": JSON.from("agc-lsp")}),
  }))
  Logs.attach_editor(state.options, state.events, JSON.get(params, "initializationOptions").unwrap_or(JSON.null()))
  Logger.info("initialized", {"encoding": encoding})
  job = Events.CatalogJob(events: state.events, agentica: state.options.agentica)
  loader = Task.spawn(&Events.load_catalog, job)
  return state.with(encoding: encoding, initialized: true, loaders: [loader], root: Workspace.root_of(params))
end

def hover(state: State, id: Json, params: Json) -> State
  case Cursor.locate(state.documents, params, state.encoding)
    ok(cursor) ->
      if Hover.settled?(state.catalog, cursor)
        Rpc.respond(id, Hover.answer(state.catalog, cursor))
        return state
      end
      return ask(state, id, "textDocument/hover", params, cursor)
    error(_) ->
      Rpc.respond(id, JSON.null())
      return state
  end
end

def definition(state: State, id: Json, params: Json) -> State
  case Cursor.locate(state.documents, params, state.encoding)
    ok(cursor) if Words.name_at?(cursor.chars, cursor.index) ->
      return ask(state, id, "textDocument/definition", params, cursor)
    ok(_) ->
      Rpc.respond(id, JSON.null())
      return state
    error(_) ->
      Rpc.respond(id, JSON.null())
      return state
  end
end

def symbols(state: State, id: Json, params: Json) -> State
  if !state.documents.get(agentica_path(document_uri(params))).ok?
    Rpc.respond(id, JSON.null())
    return state
  end
  return ask(state, id, "textDocument/documentSymbol", params, Cursor.start(state.encoding))
end

def references(state: State, id: Json, params: Json) -> State
  case Cursor.locate(state.documents, params, state.encoding)
    ok(cursor) if Words.name_at?(cursor.chars, cursor.index) ->
      return ask(state, id, "textDocument/references", params, cursor)
    ok(_) ->
      Rpc.respond(id, JSON.null())
      return state
    error(_) ->
      Rpc.respond(id, JSON.null())
      return state
  end
end

def workspace_symbols(state: State, id: Json, params: Json) -> State
  name = Fields.text(params, "query").strip
  if state.root == "" or name == "" or name.starts_with?("-")
    none: List[Json] = []
    Rpc.respond(id, JSON.array(none))
    return state
  end
  request = Workspace.Request(
    session: state.session,
    documents: state.documents,
    root: state.root,
    folder: state.folder,
    name: name,
    encoding: state.encoding,
  )
  job = Events.QueryJob(
    events: state.events,
    id: id,
    method: "workspace/symbol",
    key: state.root,
    question: Events.Question.Workspace(request),
  )
  return dropped_answer(state, Asks.submit(state.asks, job))
end

def completion(state: State, params: Json) -> Json
  case Cursor.locate(state.documents, params, state.encoding)
    ok(cursor) -> return Completion.answer(state.catalog, cursor)
    error(_) ->
      none: List[Json] = []
      return JSON.array(none)
  end
end

def ask(state: State, id: Json, method: String, params: Json, cursor: Cursor.Cursor) -> State
  uri = document_uri(params)
  case Uri.path_of(uri)
    ok(path) ->
      request = Lookup.Request(
        session: state.session,
        uri: uri,
        path: path,
        documents: state.documents,
        folder: state.folder,
        cursor: cursor,
        book: state.catalog,
      )
      job = Events.QueryJob(
        events: state.events,
        id: id,
        method: method,
        key: path,
        question: question_of(method, request, params),
      )
      return dropped_answer(state, Asks.submit(state.asks, job))
    error(_) ->
      Rpc.respond(id, JSON.null())
      return state
  end
end

def question_of(method: String, request: Lookup.Request, params: Json) -> Events.Question
  if method == "textDocument/references"
    return Events.Question.References(request, with_declaration?(params))
  end
  return Events.Question.Document(request)
end

def with_declaration?(params: Json) -> Bool
  context = Fields.value(params, "context")
  return JSON.bool(Fields.value(context, "includeDeclaration")).unwrap_or(true)
end

def cancelled(state: State, params: Json) -> State
  change = Asks.cancel(state.asks, JSON.get(params, "id").unwrap_or(JSON.null()))
  for id in change.dropped
    Rpc.fail(id, REQUEST_CANCELLED, "request cancelled")
  end
  return state.with(asks: change.plan)
end

def notification(state: State, method: String, params: Json) -> State
  if !state.initialized or state.shut_down
    return state
  end
  case method
    "textDocument/didOpen" -> return opened(state, document_uri(params), params)
    "textDocument/didChange" ->
      case changed_text(params)
        ok(text) -> return edited(state, document_uri(params), text)
        error(message) ->
          Logger.warning(message)
          return state
      end
    "textDocument/didSave" -> return saved(state, document_uri(params))
    "textDocument/didClose" -> return closed(state, document_uri(params))
    "$/cancelRequest" -> return cancelled(state, params)
    _ -> return state
  end
end

def opened(state: State, uri: String, params: Json) -> State
  case Uri.path_of(uri)
    ok(_) ->
      case document_text(params)
        ok(text) -> return keep(state, uri, text, 0)
        error(message) ->
          Logger.warning("#{message}: #{uri}")
          return state
      end
    error(message) ->
      Logger.warning(message)
      return state
  end
end

def keep(state: State, uri: String, text: String, delay_ms: Int) -> State
  path = agentica_path(uri)
  if path == ""
    return state
  end
  return revised(check(buffered(state, path, text), Schedule.delayed(uri, path, delay_ms)))
end

def buffered(state: State, path: String, text: String) -> State
  return state.with(
    documents: state.documents.put(path, text),
    session: Analysis.update(state.session, path, text),
  )
end

def revised(state: State) -> State
  return state.with(revision: state.revision + 1, plan: Schedule.supersede(state.plan, CHANGE_DELAY_MS))
end

def check(state: State, pending: Schedule.Pending) -> State
  return state.with(plan: Schedule.request(state.plan, pending))
end

def edited(state: State, uri: String, text: String) -> State
  path = agentica_path(uri)
  if path == ""
    return state
  end
  return dependents(keep(state, uri, text, CHANGE_DELAY_MS), uri, path, CHANGE_DELAY_MS)
end

def saved(state: State, uri: String) -> State
  path = Uri.path_of(uri).unwrap_or("")
  return dependents(recheck_after(state, uri, 0), uri, path, 0)
end

def dependents(state: State, uri: String, path: String, delay_ms: Int) -> State
  if path == ""
    return state
  end
  refreshed = state
  for document in state.pointing.keys
    case state.pointing.get(document)
      ok(target) ->
        if document != uri and Uri.same_path?(target, path)
          refreshed = recheck_after(refreshed, document, delay_ms)
        end
      error(_) -> next
    end
  end
  return refreshed
end

def recheck_after(state: State, uri: String, delay_ms: Int) -> State
  path = Uri.path_of(uri).unwrap_or("")
  if state.documents.get(path).ok?
    return check(state, Schedule.delayed(uri, path, delay_ms))
  end
  return state
end

def closed(state: State, uri: String) -> State
  path = ""
  case Uri.path_of(uri)
    ok(found) -> path = found
    error(message) ->
      Logger.warning(message)
      return state
  end
  if !path.ends_with?(AGENTICA_EXTENSION)
    return state
  end
  none: List[Json] = []
  publish(uri, none)
  return revised(state.with(
    plan: Schedule.forget(state.plan, uri),
    pointing: state.pointing.delete(uri),
    documents: state.documents.delete(path),
    session: Analysis.close(state.session, path),
  ))
end

def agentica_path(uri: String) -> String
  path = Uri.path_of(uri).unwrap_or("")
  if path.ends_with?(AGENTICA_EXTENSION)
    return path
  end
  return ""
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

def document_text(params: Json) -> Result[String]
  document = JSON.get(params, "textDocument").unwrap_or(JSON.null())
  case JSON.get(document, "text")
    ok(text) -> return JSON.string(text)
    error(_) -> return error("a didOpen without text")
  end
end

def changed_text(params: Json) -> Result[String]
  none: List[Json] = []
  changes = JSON.list(JSON.get(params, "contentChanges").unwrap_or(JSON.null())).unwrap_or(none)
  if changes.size == 0
    return error("a change without contentChanges")
  end
  last = changes[changes.size - 1]
  if JSON.get(last, "range").ok?
    return error("an incremental change was ignored; the server asks for full sync")
  end
  return JSON.string(JSON.get(last, "text").unwrap_or(JSON.null()))
end

def document_uri(params: Json) -> String
  document = JSON.get(params, "textDocument").unwrap_or(JSON.null())
  return JSON.string(JSON.get(document, "uri").unwrap_or(JSON.null())).unwrap_or("")
end

def log_received(message: Json, method: String) -> Void
  if !Logger.enabled?(LogLevel.Debug)
    return
  end
  case JSON.get(message, "id")
    ok(id) -> Logger.debug("received a message", {"method": method, "id": JSON.encode(id)})
    error(_) -> Logger.debug("received a message", {"method": method})
  end
end

def response?(message: Json) -> Bool
  return JSON.get(message, "result").ok? or JSON.get(message, "error").ok?
end

def object?(message: Json) -> Bool
  return JSON.kind(message) == "object"
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
