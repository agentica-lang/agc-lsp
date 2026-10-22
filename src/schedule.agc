## Decides which checks run, wait or are stale, per file. Checks run one at a time, since two refreshes of one session
## give two caches and keeping one drops the work of the other.

import Events from "events"
import Analysis from "std/analysis"
import Logger from "std/logger"

REAP_MS = 1
OVERDUE_WAIT_MS = 1

## Holds a check that waits for its due time.
export struct Pending
  ## Is the URI of the file.
  uri: String
  ## Is the path of the file.
  path: String
  ## Is the time in milliseconds when the check may start.
  due: Int
end

## Holds the check that runs.
export struct Running
  ## Is the URI of the file.
  uri: String
  ## Is the path of the file.
  path: String
  ## Is the task that runs the check.
  task: Task[Result[Void]]
end

## Holds the session that a check starts with, and its revision.
export struct Basis
  ## Is the session with the text of every open document.
  session: Analysis.Session
  ## Is the number of changes to the open documents that the session holds.
  revision: Int
end

## Holds the queue of waiting checks, the running check and the generation of each file.
export struct Plan
  ## Is the channel that receives the reports.
  events: Channel[Events.Event]
  ## Maps each URI to the generation of its latest check.
  generations: Map[String, Int]
  ## Lists the checks that wait to start.
  queue: List[Pending]
  ## Lists the check that runs, none when the session is free to refresh.
  running: List[Running]
end

## Returns a plan without checks.
export def start(events: Channel[Events.Event]) -> Plan
  generations: Map[String, Int] = {}
  return Plan(events: events, generations: generations, queue: [], running: [])
end

## Returns a check of the file that is due after the delay.
export def delayed(uri: String, path: String, delay_ms: Int) -> Pending
  return Pending(uri: uri, path: path, due: Time.now_ms() + delay_ms)
end

## Returns the plan with the check queued in place of any older check of the same file.
export def request(plan: Plan, pending: Pending) -> Plan
  cancelled = cancel(plan, pending.uri)
  if waiting?(cancelled, pending.uri)
    return cancelled.with(queue: cancelled.queue.map do |queued| newest(queued, pending) end)
  end
  return cancelled.with(queue: cancelled.queue.push(pending))
end

## Returns the plan without the checks of the file.
export def forget(plan: Plan, uri: String) -> Plan
  cancelled = cancel(plan, uri)
  return cancelled.with(queue: cancelled.queue.filter do |pending| pending.uri != uri end)
end

## Returns the plan with the running check cancelled and queued again after the delay, for a session that changed
## under it.
export def supersede(plan: Plan, delay_ms: Int) -> Plan
  current = plan
  for running in plan.running
    current = request(current, delayed(running.uri, running.path, delay_ms))
  end
  return current
end

## Returns true when the report comes from the latest check of its file.
export def current?(plan: Plan, report: Events.Report) -> Bool
  return plan.generations.get(report.uri).unwrap_or(0) == report.generation
end

## Returns the plan once the check of the file has been reported.
export def settle(plan: Plan, uri: String) -> Plan
  return plan.with(running: plan.running.filter do |running| running.uri != uri end)
end

## Returns the plan with the next check that is due started when none runs.
export def tick(plan: Plan, basis: Basis) -> Plan
  current = reap(plan)
  if current.running.size > 0
    return current
  end
  now = Time.now_ms()
  due = current.queue.filter do |pending| pending.due <= now end
  if due.size == 0
    return current
  end
  pending = due[0]
  remaining = current.queue.filter do |queued| queued.uri != pending.uri end
  return launch(current.with(queue: remaining), pending, basis)
end

## Returns how many milliseconds to wait for an event before the next check is due, at most the limit.
export def wait_ms(plan: Plan, limit: Int) -> Int
  now = Time.now_ms()
  wait = limit
  for pending in plan.queue
    left = pending.due - now
    if left <= 0 and plan.running.size == 0
      return OVERDUE_WAIT_MS
    elsif left > 0 and left < wait
      wait = left
    end
  end
  return wait
end

## Returns the plan after cancelling the running check.
export def stop(plan: Plan) -> Plan
  for running in plan.running
    Task.cancel(running.task)
  end
  return plan.with(queue: [], running: [])
end

def cancel(plan: Plan, uri: String) -> Plan
  for running in plan.running
    if running.uri == uri
      Task.cancel(running.task)
    end
  end
  generation = plan.generations.get(uri).unwrap_or(0) + 1
  kept = plan.running.filter do |running| running.uri != uri end
  return plan.with(generations: plan.generations.put(uri, generation), running: kept)
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

def launch(plan: Plan, pending: Pending, basis: Basis) -> Plan
  job = Events.Job(
    events: plan.events,
    session: basis.session,
    revision: basis.revision,
    path: pending.path,
    uri: pending.uri,
    generation: plan.generations.get(pending.uri).unwrap_or(0),
  )
  started = Running(uri: pending.uri, path: pending.path, task: Task.spawn(&Events.check, job))
  return plan.with(running: [started])
end

def reap(plan: Plan) -> Plan
  alive: List[Running] = []
  for running in plan.running
    case Task.await(running.task, REAP_MS)
      Await.Done(outcome) ->
        if outcome.ok?
          alive = alive.push(running)
        else
          Logger.err("the check of #{running.uri} crashed: #{outcome.message}")
        end
      Await.TimedOut -> alive = alive.push(running)
    end
  end
  return plan.with(running: alive)
end
