import Events from "events"
import Logger from "std/logger"

MAX_CHECKS = 4
REAP_MS = 1

export struct Pending
  uri: String
  path: String
  text: String
end

export struct Plan
  agentica: String
  events: Channel[Events.Event]
  generations: Map[String, Int]
  queue: List[Pending]
  running: Map[String, Task[Result[Void]]]
end

export def start(agentica: String, events: Channel[Events.Event]) -> Plan
  generations: Map[String, Int] = {}
  running: Map[String, Task[Result[Void]]] = {}
  return Plan(agentica: agentica, events: events, generations: generations, queue: [], running: running)
end

export def request(plan: Plan, uri: String, path: String, text: String, encoding: String) -> Plan
  cancelled = cancel(plan, uri)
  pending = Pending(uri: uri, path: path, text: text)
  queue = cancelled.queue
  if waiting?(cancelled, uri)
    queue = queue.map do |queued| newest(queued, pending) end
  else
    queue = queue.push(pending)
  end
  return fill(cancelled.with(queue: queue), encoding)
end

export def forget(plan: Plan, uri: String, encoding: String) -> Plan
  cancelled = cancel(plan, uri)
  return fill(cancelled.with(queue: cancelled.queue.filter do |pending| pending.uri != uri end), encoding)
end

export def current?(plan: Plan, report: Events.Report) -> Bool
  return plan.generations.get(report.uri).unwrap_or(0) == report.generation
end

export def settle(plan: Plan, uri: String, encoding: String) -> Plan
  return fill(plan.with(running: plan.running.delete(uri)), encoding)
end

export def tick(plan: Plan, encoding: String) -> Plan
  return fill(plan, encoding)
end

export def stop(plan: Plan) -> Plan
  for task in plan.running.values
    Task.cancel(task)
  end
  running: Map[String, Task[Result[Void]]] = {}
  return plan.with(queue: [], running: running)
end

def cancel(plan: Plan, uri: String) -> Plan
  running = plan.running.get(uri)
  if running.ok?
    Task.cancel(running.unwrap!)
  end
  generation = plan.generations.get(uri).unwrap_or(0) + 1
  return plan.with(generations: plan.generations.put(uri, generation), running: plan.running.delete(uri))
end

def newest(queued: Pending, pending: Pending) -> Pending
  if queued.uri == pending.uri
    return pending
  end
  return queued
end

def waiting?(plan: Plan, uri: String) -> Bool
  return plan.queue.filter do |pending| pending.uri == uri end.size > 0
end

def fill(plan: Plan, encoding: String) -> Plan
  current = plan
  if current.queue.size > 0 and current.running.size >= MAX_CHECKS
    current = reap(current)
  end
  while current.queue.size > 0 and current.running.size < MAX_CHECKS
    pending = current.queue[0]
    current = launch(current.with(queue: current.queue.drop(1)), pending, encoding)
  end
  return current
end

def launch(plan: Plan, pending: Pending, encoding: String) -> Plan
  job = Events.Job(
    events: plan.events,
    agentica: plan.agentica,
    encoding: encoding,
    path: pending.path,
    text: pending.text,
    uri: pending.uri,
    generation: plan.generations.get(pending.uri).unwrap_or(0),
  )
  return plan.with(running: plan.running.put(pending.uri, Task.spawn(&Events.check, job)))
end

def reap(plan: Plan) -> Plan
  alive: Map[String, Task[Result[Void]]] = {}
  for uri in plan.running.keys
    task = plan.running.get(uri).unwrap!
    case Task.await(task, REAP_MS)
      Await.Done(outcome) ->
        if !outcome.ok?
          Logger.err("the check of #{uri} crashed: #{outcome.message}")
        end
      Await.TimedOut -> alive = alive.put(uri, task)
    end
  end
  return plan.with(running: alive)
end
