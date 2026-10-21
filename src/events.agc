## Defines the events of the server loop and the tasks that send them.

import Catalog from "catalog"
import Check from "check"
import Rpc from "rpc"
import Logger from "std/logger"

SEND_TIMEOUT_MS = 10_000

## Holds the outcome of one check of a file, for the generation that started it.
export struct Report
  uri: String
  generation: Int
  outcome: Result[List[Json]]
end

## Names what the server loop receives: input, a finished check, the catalog or a log line.
export enum Event
  Input(Rpc.Incoming)
  Checked(Report)
  Cataloged(Result[Catalog.Book])
  Log(LogEvent)
end

## Holds what a check task needs: the file, its text and the channel for the result.
export struct Job
  events: Channel[Event]
  agentica: String
  encoding: String
  path: String
  text: String
  uri: String
  generation: Int
end

## Holds what the catalog task needs.
export struct CatalogJob
  events: Channel[Event]
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
  if outcome.ok?
    Logger.info("loaded the builtin catalog", {"builtins": outcome.unwrap!.entries.size.to_s})
  else
    Logger.warning("cannot load the builtin catalog from #{job.agentica}: #{outcome.message}")
  end
  deliver(job.events, Event.Cataloged(outcome))
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
