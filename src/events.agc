import Check from "check"
import Logger from "std/logger"
import Rpc from "rpc"

SEND_TIMEOUT_MS = 10000

export struct Report
  uri: String
  generation: Int
  outcome: Result[List[Json]]
end

export enum Event
  Input(Rpc.Incoming)
  Checked(Report)
  Log(LogEvent)
end

export struct Job
  events: Channel[Event]
  agentica: String
  encoding: String
  path: String
  uri: String
  generation: Int
end

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

export def check(job: Job) -> Result[Void]
  started = Time.now_ms()
  if Logger.enabled?(LogLevel.Debug)
    Logger.debug("check started", {"uri": job.uri, "generation": job.generation.to_s})
  end
  outcome = Check.diagnostics(job.agentica, job.path, job.encoding)
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
