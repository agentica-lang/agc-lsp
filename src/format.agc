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

CHUNK_BYTES = 1_000_000

MS_PER_KB = 60

SHORTEST_WAIT_MS = 1

def formatted(request: Request) -> Result[String]
  limit = FORMAT_TIMEOUT_MS + request.text.length / 1000 * MS_PER_KB
  options = Process.Options(timeout_ms: limit, chdir: folder_of(request.path))
  helper = try Process.spawn_captured(executable(request.agentica), ["fmt", "-"], options)
  outcome = run(helper, request.text, Time.now_ms() + limit)
  Process.close(helper)
  return outcome
end

def run(helper: Process, text: String, deadline: Int) -> Result[String]
  try send_all(helper, text, deadline)
  try Process.close_stdin(helper, remaining(deadline))
  formatted = try read_all(helper, deadline)
  output = try Process.output(helper, remaining(deadline))
  status = try Process.wait(helper, remaining(deadline))
  if status != 0
    return error(output.stderr.split("\n")[0])
  end

  return ok(formatted)
end

def read_all(helper: Process, deadline: Int) -> Result[String]
  parts: List[Bytes] = []
  while true
    part = try Process.read_bytes(helper, CHUNK_BYTES, remaining(deadline))
    parts = parts.push(part)
    if part.size < CHUNK_BYTES
      return String.from_bytes(Bytes.concat(parts))
    end
  end

  return error("unreachable")
end

def send_all(helper: Process, text: String, deadline: Int) -> Result[Void]
  lines = text.split("\n")
  chunk: List[String] = []
  size = 0
  for index in 0...lines.size
    piece = lines[index]
    if index < lines.size - 1
      piece = "#{piece}\n"
    end

    width = piece.bytes.size
    if width > CHUNK_BYTES
      return error("a line is longer than #{CHUNK_BYTES} bytes")
    end

    if size + width > CHUNK_BYTES
      try Process.send(helper, chunk.join(""), remaining(deadline))
      chunk = []
      size = 0
    end

    chunk = chunk.push(piece)
    size += width
  end

  return Process.send(helper, chunk.join(""), remaining(deadline))
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
  if parts.size <= 2 and parts[0].end_with?(":")
    return "#{parts[0]}/"
  elsif parts.size <= 2
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
