import Check from "check"
import Rpc from "rpc"

SEND_TIMEOUT_MS = 10000

export struct Report
  uri: String
  generation: Int
  diagnostics: List[Json]
end

export enum Event
  Input(Rpc.Incoming)
  Checked(Report)
end

export struct Job
  events: Channel[Event]
  agentica: String
  encoding: String
  path: String
  uri: String
  generation: Int
end

export def read_input(events: Channel[Event]) -> Void
  while true
    incoming = Rpc.read()
    deliver(events, Event.Input(incoming))
    if last?(incoming)
      return
    end
  end
end

export def check(job: Job) -> Void
  found = Check.diagnostics(job.agentica, job.path, job.encoding)
  deliver(job.events, Event.Checked(Report(uri: job.uri, generation: job.generation, diagnostics: found)))
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
