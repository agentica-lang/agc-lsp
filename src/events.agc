## Defines the events of the server loop and the tasks that send them.

import Catalog from "catalog"
import Lookup from "lookup"
import Rpc from "rpc"
import Analysis from "std/analysis"
import Logger from "std/logger"
import Symbols from "symbols"
import Workspace from "workspace"

SEND_TIMEOUT_MS = 10_000

## Holds the outcome of one check of a file, for the generation that started it.
export struct Report
  ## Is the URI of the checked file.
  uri: String
  ## Is the generation of the check, to tell newer checks from older.
  generation: Int
  ## Is the revision of the session that the check started with.
  revision: Int
  ## Is that session with the checked file linked and checked in its cache.
  session: Analysis.Session
  ## Is the answer of the check.
  checked: Analysis.Checked
end

## Holds the answer to a request that needed a query, for the request with that id.
export struct Answer
  ## Is the id of the request.
  id: Json
  ## Is the result to send, null when there is nothing to show.
  result: Json
end

## Names what the server loop receives: input, a finished check, an answer, the catalog or a log line.
export enum Event
  ## Is a message or a framing problem from the input.
  Input(Rpc.Incoming)
  ## Is a finished check.
  Checked(Report)
  ## Is the answer to a definition, references, hover, document symbol or workspace symbol request.
  Answered(Answer)
  ## Is the loaded catalog, or the reason it failed.
  Cataloged(Result[Catalog.Book])
  ## Is a log line to send to the editor.
  Log(LogEvent)
end

## Holds what a check task needs: the session, the file and the channel for the result.
export struct Job
  ## Is the channel that receives the report.
  events: Channel[Event]
  ## Is the session with the text of every open document.
  session: Analysis.Session
  ## Is the revision of the session.
  revision: Int
  ## Is the path of the file.
  path: String
  ## Is the URI of the file.
  uri: String
  ## Is the generation of the check.
  generation: Int
end

## Is what a query asks.
export enum Question
  ## Is a question about a document and a position in it: definition, hover or document symbols.
  Document(Lookup.Request)
  ## Is a question about the uses of the name at a position, with true to include its declaration.
  References(Lookup.Request, Bool)
  ## Is a search for a name in the files of the workspace.
  Workspace(Workspace.Request)
end

## Holds what the task of a definition, references, hover, document symbol or workspace symbol request needs.
export struct QueryJob
  ## Is the channel that receives the answer.
  events: Channel[Event]
  ## Is the id of the request.
  id: Json
  ## Is the method of the request.
  method: String
  ## Is what a newer request of the same method replaces: the path of the document, or the folder of the workspace.
  key: String
  ## Is the question.
  question: Question
end

## Holds what the catalog task needs.
export struct CatalogJob
  ## Is the channel that receives the catalog.
  events: Channel[Event]
  ## Is the executable that prints the catalog.
  agentica: String
end

## Sends each incoming message to the channel until the input ends, and returns ok.
export def read_input(events: Channel[Event]) -> Result[Void]
  while true
    incoming = Rpc.read()
    deliver(events, Event.Input(incoming))
    if last?(incoming)
      return ok()
    end
  end

  return ok()
end

## Refreshes the session for the file of the job, checks it and sends the report to the channel, returning ok.
export def check(job: Job) -> Result[Void]
  started = Time.now_ms()
  if Logger.enabled?(LogLevel.Debug)
    Logger.debug("check started", {"uri": job.uri, "generation": job.generation.to_s})
  end

  refreshed = Analysis.refresh(job.session, job.path)
  checked = Analysis.check(refreshed, job.path)
  if Logger.enabled?(LogLevel.Debug)
    fields = {
      "uri": job.uri,
      "generation": job.generation.to_s,
      "ms": (Time.now_ms() - started).to_s,
      "passed": checked.passed.to_s,
    }
    Logger.debug("check finished", fields)
  end

  report = Report(
    uri: job.uri,
    generation: job.generation,
    revision: job.revision,
    session: refreshed,
    checked: checked,
  )
  deliver(job.events, Event.Checked(report))
  return ok()
end

## Loads the catalog and sends it to the channel, returning ok.
export def load_catalog(job: CatalogJob) -> Result[Void]
  outcome = Catalog.load(job.agentica)
  case outcome
    ok(book) -> Logger.info("loaded the builtin catalog", {"builtins": book.entries.size.to_s})
    error(message) -> Logger.warning("cannot load the builtin catalog from #{job.agentica}: #{message}")
  end

  deliver(job.events, Event.Cataloged(outcome))
  return ok()
end

## Answers a query and sends the answer to the channel, returning ok.
export def answer_query(job: QueryJob) -> Result[Void]
  case job.question
    Question.Document(request) -> return answer_document(job, request)
    Question.References(request, with_declaration) ->
      return settle(job.events, job.id, "references", Lookup.references(request, with_declaration))
    Question.Workspace(request) ->
      return settle(job.events, job.id, "workspace symbols", Workspace.answer(request))
  end
end

def answer_document(job: QueryJob, request: Lookup.Request) -> Result[Void]
  case job.method
    "textDocument/definition" -> return settle(job.events, job.id, "definition", Lookup.definition(request))
    "textDocument/hover" -> return settle(job.events, job.id, "hover", Lookup.hover(request))
    _ ->
      return settle(job.events, job.id, "document symbols", Symbols.answer(request))
  end
end

def settle(events: Channel[Event], id: Json, what: String, outcome: Result[Json]) -> Result[Void]
  result = JSON.null()
  case outcome
    ok(found) -> result = found
    error(message) -> Logger.warning("cannot answer the request for the #{what}: #{message}")
  end

  deliver(events, Event.Answered(Answer(id: id, result: result)))
  return ok()
end

def last?(incoming: Rpc.Incoming) -> Bool
  case incoming
    Rpc.Incoming.End -> return true
    Rpc.Incoming.Unframed(_) -> return true
    Rpc.Incoming.Message(_) -> return false
    Rpc.Incoming.Malformed(_) -> return false
  end
end

def deliver(events: Channel[Event], event: Event) -> Void
  while !events.closed?
    if events.send(event, SEND_TIMEOUT_MS).ok?
      return
    end
  end
end
