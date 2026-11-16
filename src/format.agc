## Formats the text of a buffer with `agentica fmt -`, for textDocument/formatting.

import {UTF16, utf16_width} from "columns"
import Logger from "std/logger"

## Holds what a formatting needs.
struct Request
  ## Is the executable that formats.
  agentica: String
  ## Is the path of the file: agentica reads the style from the manifest of its folder.
  path: String
  ## Is the text of the buffer.
  text: String
  ## Is the position encoding of the session.
  encoding: String
end

## Returns the edits that format the buffer: one that replaces the whole text, or none when the text is already
## formatted or cannot be formatted (the reason is logged).
def answer(request: Request) -> Result[JSON.Value]
  edits: List[JSON.Value] = []
  case formatted(request)
    ok(text) ->
      if text != request.text
        edits = [JSON.object({"range": whole(request), "newText": JSON.from(text)})]
      end

    error(failure) -> Logger.info("cannot format #{request.path}: #{failure.message}")
  end

  return ok(JSON.array(edits))
end

private

FORMAT_TIMEOUT_MS = 10_000

SHORTEST_WAIT_MS = 1

def formatted(request: Request) -> Result[String]
  options = Process.Options(timeout_ms: FORMAT_TIMEOUT_MS, chdir: folder_of(request.path))
  helper = try Process.spawn_captured(executable(request.agentica), ["fmt", "-"], options)
  outcome = run(helper, request.text, Time.now_ms() + FORMAT_TIMEOUT_MS)
  Process.close(helper)
  return outcome
end

def run(helper: Process, text: String, deadline: Int) -> Result[String]
  try Process.send(helper, text, remaining(deadline))
  try Process.close_stdin(helper, remaining(deadline))
  output = try Process.output(helper, remaining(deadline))
  status = try Process.wait(helper, remaining(deadline))
  if status != 0
    return error(output.stderr.split("\n")[0])
  elsif output.truncated
    return error("the formatted text is too long")
  end

  return ok(output.stdout)
end

def remaining(deadline: Int) -> Int
  left = deadline - Time.now_ms()
  if left < SHORTEST_WAIT_MS
    return SHORTEST_WAIT_MS
  end

  return left
end

def executable(agentica: String) -> String
  if agentica.include?("/") or agentica.include?("\\")
    return Path.resolve(agentica).unwrap_or(agentica)
  end

  return agentica
end

def folder_of(path: String) -> String
  parts = path.split("/")
  if parts.size <= 2
    return "/"
  end

  return parts.take(parts.size - 1).join("/")
end

def whole(request: Request) -> JSON.Value
  lines = request.text.split("\n")
  last = lines[lines.size - 1]
  character = last.split("").size
  if request.encoding == UTF16
    character = utf16_width(last, character)
  end

  return JSON.object({
    "start": JSON.object({"line": JSON.from(0), "character": JSON.from(0)}),
    "end": JSON.object({"line": JSON.from(lines.size - 1), "character": JSON.from(character)}),
  })
end
