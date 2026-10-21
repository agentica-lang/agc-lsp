## Decides which queries for requests run, wait or are superseded, and which request ids are dropped.

import Events from "events"
import Logger from "std/logger"

MAX_QUERIES = 4
REAP_MS = 1
SUPERSEDED_METHODS = Set.new(["textDocument/hover", "textDocument/definition"])

## Holds a query that runs in a task.
export struct Running
  ## Is the query.
  job: Events.QueryJob
  ## Is the task that runs it.
  task: Task[Result[Void]]
end

## Holds the queries that wait for a free place, in the order they came, and the ones that run.
export struct Plan
  ## Lists the queries that wait.
  queue: List[Events.QueryJob]
  ## Lists the queries that run, at most four.
  running: List[Running]
end

## Holds a plan and the ids of the requests that the change dropped without an answer.
export struct Change
  ## Is the plan after the change.
  plan: Plan
  ## Lists the ids of the dropped requests, which still need a reply.
  dropped: List[Json]
end

## Returns a plan without queries.
export def start() -> Plan
  return Plan(queue: [], running: [])
end

## Returns the plan with the query queued, and the older queries of the same document and method dropped.
export def submit(plan: Plan, job: Events.QueryJob) -> Change
  path = job.request.buffer.path
  if !SUPERSEDED_METHODS.include?(job.method)
    return fill(Change(plan: plan.with(queue: plan.queue.push(job)), dropped: []))
  end
  older = drop_where(plan) do |old| old.method == job.method and old.request.buffer.path == path end
  return fill(older.with(plan: older.plan.with(queue: older.plan.queue.push(job))))
end

## Returns the plan once the request has been answered, or an error when the request is not known.
export def settle(plan: Plan, id: Json) -> Result[Plan]
  if !known?(plan, id)
    return error("no query for the request #{id}")
  end
  kept = plan.running.filter do |running| !same?(running.job.id, id) end
  return ok(fill(Change(plan: plan.with(running: kept), dropped: [])).plan)
end

## Returns the plan without the request, whose id is dropped, or the plan as it is when the request is not known.
export def cancel(plan: Plan, id: Json) -> Change
  return fill(drop_where(plan) do |old| same?(old.id, id) end)
end

## Returns the plan without queries and the ids of all the requests that had not been answered.
export def abandon(plan: Plan) -> Change
  dropped: List[Json] = []
  for running in plan.running
    Task.cancel(running.task)
    dropped = dropped.push(running.job.id)
  end
  for job in plan.queue
    dropped = dropped.push(job.id)
  end
  return Change(plan: start(), dropped: dropped)
end

## Returns the plan without the queries whose task ended in a crash, whose ids are dropped.
export def reap(plan: Plan) -> Change
  alive: List[Running] = []
  dropped: List[Json] = []
  for running in plan.running
    case Task.await(running.task, REAP_MS)
      Await.Done(outcome) ->
        if !outcome.ok?
          Logger.err("the query for request #{running.job.id} crashed: #{outcome.message}")
          dropped = dropped.push(running.job.id)
        else
          alive = alive.push(running)
        end
      Await.TimedOut -> alive = alive.push(running)
    end
  end
  return fill(Change(plan: plan.with(running: alive), dropped: dropped))
end

def known?(plan: Plan, id: Json) -> Bool
  return plan.running.filter do |running| same?(running.job.id, id) end.size > 0
end

def same?(a: Json, b: Json) -> Bool
  return a.to_s == b.to_s
end

def drop_where(plan: Plan, matches: Fn[Events.QueryJob, Bool]) -> Change
  dropped: List[Json] = []
  kept: List[Running] = []
  for running in plan.running
    if matches.call(running.job)
      Task.cancel(running.task)
      dropped = dropped.push(running.job.id)
    else
      kept = kept.push(running)
    end
  end
  waiting = plan.queue.filter do |job| !matches.call(job) end
  for job in plan.queue
    if matches.call(job)
      dropped = dropped.push(job.id)
    end
  end
  return Change(plan: Plan(queue: waiting, running: kept), dropped: dropped)
end

def fill(change: Change) -> Change
  current = change.plan
  while current.running.size < MAX_QUERIES and current.queue.size > 0
    job = current.queue[0]
    started = Running(job: job, task: Task.spawn(&Events.answer_query, job))
    current = current.with(queue: current.queue.drop(1), running: current.running.push(started))
  end
  return change.with(plan: current)
end
