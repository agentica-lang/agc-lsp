## Decides which checks run, wait or are stale, per file.

import Events from "events"
import Logger from "std/logger"

MAX_CHECKS = 4
REAP_MS = 1
OVERDUE_WAIT_MS = 1

## Holds a check that waits for its due time.
export struct Pending
  uri: String
  path: String
  text: String
  due: Int
end

## Holds the queue of waiting checks, the running tasks and the generation of each file.
export struct Plan
  agentica: String
  events: Channel[Events.Event]
  generations: Map[String, Int]
  queue: List[Pending]
  running: Map[String, Task[Result[Void]]]
end

## Returns a plan without checks.
export def start(agentica: String, events: Channel[Events.Event]) -> Plan
  generations: Map[String, Int] = {}
  running: Map[String, Task[Result[Void]]] = {}
  return Plan(agentica: agentica, events: events, generations: generations, queue: [], running: running)
end

## Returns a check of the text that is due after the delay.
export def delayed(uri: String, path: String, text: String, delay_ms: Int) -> Pending
  return Pending(uri: uri, path: path, text: text, due: Time.now_ms() + delay_ms)
end

## Returns the plan with the check queued in place of any older check of the same file.
export def request(plan: Plan, pending: Pending, encoding: String) -> Plan
  uri = pending.uri
  cancelled = cancel(plan, uri)
  queue = cancelled.queue
  if waiting?(cancelled, uri)
    queue = queue.map do |queued| newest(queued, pending) end
  else
    queue = queue.push(pending)
  end
  return fill(cancelled.with(queue: queue), encoding)
end

## Returns the plan without the checks of the file.
export def forget(plan: Plan, uri: String, encoding: String) -> Plan
  cancelled = cancel(plan, uri)
  return fill(cancelled.with(queue: cancelled.queue.filter do |pending| pending.uri != uri end), encoding)
end

## Returns true when the report comes from the latest check of its file.
export def current?(plan: Plan, report: Events.Report) -> Bool
  return plan.generations.get(report.uri).unwrap_or(0) == report.generation
end

## Returns the plan once the check of the file has been reported.
export def settle(plan: Plan, uri: String, encoding: String) -> Plan
  return fill(plan.with(running: plan.running.delete(uri)), encoding)
end

## Returns the plan with the checks that are due started.
export def tick(plan: Plan, encoding: String) -> Plan
  return fill(plan, encoding)
end

## Returns how many milliseconds to wait for an event before the next check is due, at most the limit.
export def wait_ms(plan: Plan, limit: Int) -> Int
  now = Time.now_ms()
  wait = limit
  for pending in plan.queue
    left = pending.due - now
    if left <= 0 and plan.running.size < MAX_CHECKS
      return OVERDUE_WAIT_MS
    elsif left > 0 and left < wait
      wait = left
    end
  end
  return wait
end

## Returns the plan after cancelling every running check.
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
  now = Time.now_ms()
  while current.running.size < MAX_CHECKS
    due = current.queue.filter do |pending| pending.due <= now end
    if due.size == 0
      break
    end
    pending = due[0]
    remaining = current.queue.filter do |queued| queued.uri != pending.uri end
    current = launch(current.with(queue: remaining), pending, encoding)
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
