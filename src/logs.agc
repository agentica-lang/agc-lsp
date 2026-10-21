import Events from "events"
import {DEFAULT_CLIENT_LEVEL, DEFAULT_LEVEL, Options, level?} from "options"
import Logger from "std/logger"
import Rpc from "rpc"

MAIN_TASK = 1
FILE_TIMEOUT_MS = 1000
SEND_TIMEOUT_MS = 1000

struct Chosen
  level: LogLevel
  problem: String
end

export def start(options: Options) -> Options
  usable = writable(options)
  level = choose(usable.level, JSON.null(), "logLevel", DEFAULT_LEVEL).level
  install(usable, level)
  Logger.set_level(level)
  for problem in usable.problems
    Logger.warning(problem)
  end
  Logger.info("starting", {"agentica": usable.agentica})
  return usable
end

export def attach_editor(options: Options, events: Channel[Events.Event], asked: Json) -> Void
  stderr = choose(options.level, asked, "logLevel", DEFAULT_LEVEL)
  editor = choose(options.client_level, asked, "clientLogLevel", DEFAULT_CLIENT_LEVEL)
  install(options, stderr.level)
  _ = Logger.detach("editor")
  _ = Logger.attach("editor", editor.level) do |event| to_editor(events, event) end
  Logger.set_level(lower(stderr.level, editor.level))
  for problem in [stderr.problem, editor.problem]
    if problem != ""
      Logger.warning(problem)
    end
  end
end

export def write_to_editor(event: LogEvent) -> Void
  Rpc.log_message(editor_type(event.level), editor_text(event))
end

def writable(options: Options) -> Options
  if options.file == ""
    return options
  end
  case File.append_text(options.file, "", FILE_TIMEOUT_MS)
    ok(_) -> return options
    error(message) ->
      problem = "cannot write the log file #{options.file}: #{message}"
      return options.with(file: "", problems: options.problems.push(problem))
  end
end

def install(options: Options, level: LogLevel) -> Void
  _ = Logger.detach("console")
  _ = Logger.detach("stderr")
  _ = Logger.detach("file")
  if options.format == "json"
    _ = Logger.attach("stderr", level, &Logger.stderr_json)
  else
    _ = Logger.attach("stderr", level, &Logger.stderr_text)
  end
  if options.file != ""
    path = options.file
    _ = Logger.attach("file", level) do |event|
      _ = File.append_text(path, "#{Logger.format_json(event)}\n", FILE_TIMEOUT_MS)
    end
  end
end

def to_editor(events: Channel[Events.Event], event: LogEvent) -> Void
  if event.task == MAIN_TASK
    write_to_editor(event)
  else
    _ = events.send(Events.Event.Log(event), SEND_TIMEOUT_MS)
  end
end

def choose(given: String, asked: Json, key: String, default: String) -> Chosen
  fallback = level_named(default)
  if given != ""
    return Chosen(level: level_named(given), problem: "")
  end
  case JSON.get(asked, key)
    error(_) -> return Chosen(level: fallback, problem: "")
    ok(value) ->
      name = JSON.string(value).unwrap_or(JSON.encode(value))
      if name == "null"
        return Chosen(level: fallback, problem: "")
      elsif level?(name)
        return Chosen(level: level_named(name), problem: "")
      end
      problem = "unknown log level #{name} for #{key} in the initializationOptions; keeping the default"
      return Chosen(level: fallback, problem: problem)
  end
end

def level_named(name: String) -> LogLevel
  case name
    "debug" -> return LogLevel.Debug
    "info" -> return LogLevel.Info
    "warning" -> return LogLevel.Warning
    "error" -> return LogLevel.Error
    _ -> return LogLevel.Warning
  end
end

def lower(a: LogLevel, b: LogLevel) -> LogLevel
  if rank(a) <= rank(b)
    return a
  end
  return b
end

def rank(level: LogLevel) -> Int
  case level
    LogLevel.Debug -> return 0
    LogLevel.Info -> return 1
    LogLevel.Warning -> return 2
    LogLevel.Error -> return 3
  end
end

def editor_type(level: LogLevel) -> Int
  case level
    LogLevel.Error -> return 1
    LogLevel.Warning -> return 2
    LogLevel.Info -> return 3
    LogLevel.Debug -> return 4
  end
end

def editor_text(event: LogEvent) -> String
  shown = event.fields.keys.map do |key| "#{key}=#{event.fields.get(key).unwrap!}" end
  if shown.size == 0
    return event.message
  end
  return "#{event.message} #{shown.join(" ")}"
end
