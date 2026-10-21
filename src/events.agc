## Defines the events of the server loop and the tasks that send them.

import Catalog from "catalog"
import Check from "check"
import Lookup from "lookup"
import Query from "query"
import Rpc from "rpc"
import Logger from "std/logger"
import Symbols from "symbols"

SEND_TIMEOUT_MS = 10_000

## Holds the outcome of one check of a file, for the generation that started it.
export struct Report
  ## Is the URI of the checked file.
  uri: String
  ## Is the generation of the check, to tell newer checks from older.
  generation: Int
  ## Is the diagnostics, or the reason the check failed.
  outcome: Result[List[Json]]
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
  ## Is the answer to a definition, hover or document symbol request.
  Answered(Answer)
  ## Is the loaded catalog, or the reason it failed.
  Cataloged(Result[Catalog.Book])
  ## Is a log line to send to the editor.
  Log(LogEvent)
end

## Holds what a check task needs: the file, its text and the channel for the result.
export struct Job
  ## Is the channel that receives the report.
  events: Channel[Event]
  ## Is the executable that runs the check.
  agentica: String
  ## Is the position encoding of the diagnostics.
  encoding: String
  ## Is the path of the file.
  path: String
  ## Is the text of the buffer.
  text: String
  ## Is the URI of the file.
  uri: String
  ## Is the generation of the check.
  generation: Int
end

## Holds what the task of a definition or hover request needs: the channel, the request id and the question.
export struct LookupJob
  ## Is the channel that receives the answer.
  events: Channel[Event]
  ## Is the id of the request.
  id: Json
  ## Is the question.
  request: Lookup.Request
end

## Holds what the task of a document symbol request needs.
export struct SymbolsJob
  ## Is the channel that receives the answer.
  events: Channel[Event]
  ## Is the id of the request.
  id: Json
  ## Is the executable that prints the outline.
  agentica: String
  ## Is the document, as the editor shows it.
  buffer: Query.Buffer
  ## Is the position encoding of the ranges.
  encoding: String
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

## Checks the file of the job and sends the report to the channel, returning ok.
export def check(job: Job) -> Result[Void]
  started = Time.now_ms()
  if Logger.enabled?(LogLevel.Debug)
    Logger.debug("check started", {"uri": job.uri, "generation": job.generation.to_s})
  end
  outcome = Check.diagnostics(job.agentica, job.path, job.text, job.encoding)
  if Logger.enabled?(LogLevel.Debug)
    fields = {
      "uri": job.uri,
      "generation": job.generation.to_s,
      "ms": (Time.now_ms() - started).to_s,
      "ok": outcome.ok?.to_s,
    }
    Logger.debug("check finished", fields)
  end
  deliver(job.events, Event.Checked(Report(uri: job.uri, generation: job.generation, outcome: outcome)))
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

## Answers a definition request and sends the answer to the channel, returning ok.
export def answer_definition(job: LookupJob) -> Result[Void]
  return settle(job.events, job.id, "definition", Lookup.definition(job.request))
end

## Answers a hover request and sends the answer to the channel, returning ok.
export def answer_hover(job: LookupJob) -> Result[Void]
  return settle(job.events, job.id, "hover", Lookup.hover(job.request))
end

## Answers a document symbol request and sends the answer to the channel, returning ok.
export def answer_symbols(job: SymbolsJob) -> Result[Void]
  return settle(job.events, job.id, "document symbols", Symbols.answer(job.agentica, job.buffer, job.encoding))
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
