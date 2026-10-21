## Runs the agentica binary on a text and returns what it printed.

SHORTEST_WAIT_MS = 1
CHUNK_BYTES = 1_048_576
SINGLE_SEND_CHARS = 262_144

## Holds what a finished process printed and how it ended.
export struct Output
  ## Is the exit status.
  status: Int
  ## Is the text on standard output.
  stdout: String
  ## Is the text on standard error.
  stderr: String
  ## Is the reason the text could not be sent, or an empty text when all of it was sent.
  unsent: String
end

## Returns the output of the command that reads the text on standard input, or an error when it cannot be run.
export def run(
  command: String,
  arguments: List[String],
  text: String,
  deadline: Int,
  dir: String = ".",
) -> Result[Output]
  child = try Process.spawn_captured(command, arguments, dir, remaining(deadline))
  result = collect(child, text, deadline)
  Process.close(child)
  return result
end

## Returns the milliseconds left until the deadline, at least one.
export def remaining(deadline: Int) -> Int
  left = deadline - Time.now_ms()
  if left < SHORTEST_WAIT_MS
    return SHORTEST_WAIT_MS
  end
  return left
end

def collect(child: Process, text: String, deadline: Int) -> Result[Output]
  sent = feed(child, text, deadline)
  captured = Process.output(child, remaining(deadline))
  if !captured.ok? and !sent.ok?
    return error("cannot send the buffer: #{sent.message}")
  end
  output = try captured
  status = try Process.wait(child, remaining(deadline))
  unsent = ""
  if !sent.ok?
    unsent = "cannot send the buffer: #{sent.message}"
  end
  return ok(Output(status: status, stdout: output.stdout, stderr: output.stderr, unsent: unsent))
end

def feed(child: Process, text: String, deadline: Int) -> Result[Void]
  if text.length <= SINGLE_SEND_CHARS
    try Process.send(child, text, remaining(deadline))
    return Process.close_stdin(child, remaining(deadline))
  end
  rest = text.to_bytes
  while rest.size > 0
    try Process.send_bytes(child, rest.take(CHUNK_BYTES), remaining(deadline))
    rest = rest.drop(CHUNK_BYTES)
  end
  return Process.close_stdin(child, remaining(deadline))
end
