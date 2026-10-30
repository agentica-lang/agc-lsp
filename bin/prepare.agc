## Prints the path of the compiled server for the launchers, compiling it first when the cache has none:
## `prepare.agc ROOT AGENTICA`.

LIBRARY = "agc-lsp"
PROGRAM_SUFFIX = ".agcb"
STAMP_SUFFIX = ".used"
LEFTOVER_PREFIX = "compiling."
PARTIAL_SUFFIX = ".tmp"
SOURCE_SUFFIX = ".agc"
WINDOWS = "windows"
KEEP_SECONDS = 2_592_000
PARTIAL_SECONDS = 3_600
IO_TIMEOUT_MS = 20_000
COMPILE_TIMEOUT_MS = 300_000
CACHE_OVERRIDE = "AGC_LSP_CACHE"

struct Cache
  folder: String
  program: String
end

struct Finished
  status: Int
  stdout: String
  stderr: String
end

def main() -> Void
  args = System.args()
  if args.size != 2
    fail("usage: prepare.agc ROOT AGENTICA")
  end

  case prepared(args[0], args[1])
    ok(program) -> puts(program)
    error(message) -> fail(message)
  end
end

def fail(message: String) -> Void
  IO.warn("agc-lsp: #{message}")
  System.exit(1)
end

def prepared(root: String, agentica: String) -> Result[String]
  version = try version_of(agentica)
  key = try cache_key(root, Path.real(agentica).unwrap_or(agentica), version)
  cache = try cache_for(key)
  try make_folder(cache.folder)
  if !File.stat(cache.program, IO_TIMEOUT_MS).ok?
    try compile(root, agentica, key, cache)
    prune(cache, Time.now_ms() / 1000)
  end

  stamp(cache)
  return ok(cache.program)
end

def make_folder(folder: String) -> Result[Void]
  if File.stat(folder, IO_TIMEOUT_MS).ok?
    return ok()
  end

  parent = try Path.resolve("#{folder}/..")
  try Dir.mkdir(parent, IO_TIMEOUT_MS)
  made = Dir.mkdir_private(folder, IO_TIMEOUT_MS)
  if made.ok? or File.stat(folder, IO_TIMEOUT_MS).ok?
    return ok()
  end

  return made
end

def version_of(binary: String) -> Result[String]
  done = try run(binary, ["--version"], IO_TIMEOUT_MS)
  if done.status != 0
    return error("cannot run '#{binary} --version': #{done.stderr.trim}")
  end

  return ok(done.stdout.trim)
end

def run(binary: String, args: List[String], timeout_ms: Int) -> Result[Finished]
  child = try Process.spawn_captured(binary, args, ".", timeout_ms)
  done = finish(child, timeout_ms)
  Process.close(child)
  return done
end

def finish(child: Process, timeout_ms: Int) -> Result[Finished]
  output = try Process.output(child, timeout_ms)
  status = try Process.wait(child, timeout_ms)
  return ok(Finished(status: status, stdout: output.stdout, stderr: output.stderr))
end

def cache_key(root: String, binary: String, version: String) -> Result[String]
  folder = try Path.join([root, "src"])
  names = try Dir.list(folder, IO_TIMEOUT_MS)
  sources = names.filter do |name| name.ends_with?(SOURCE_SUFFIX) end
  pieces = ["#{binary}\n#{version}\n"]
  for name in sources
    path = try Path.join([folder, name])
    text = try File.read_text(path, IO_TIMEOUT_MS)
    pieces = pieces.push("#{name}\n#{text}")
  end

  return ok(Digest.sha256_hexdigest(pieces.join("").bytes))
end

def cache_for(key: String) -> Result[Cache]
  folder = try cache_folder()
  program = try Path.join([folder, "#{key}#{PROGRAM_SUFFIX}"])
  return ok(Cache(folder: folder, program: program))
end

def cache_folder() -> Result[String]
  override = System.env(CACHE_OVERRIDE).unwrap_or("")
  if override != ""
    return ok(override)
  end

  base = try cache_base()
  return Path.join([base, LIBRARY])
end

def cache_base() -> Result[String]
  if System.os() == WINDOWS
    return environment("LOCALAPPDATA")
  end

  configured = System.env("XDG_CACHE_HOME").unwrap_or("")
  if configured != ""
    return ok(configured)
  end

  home = try environment("HOME")
  return Path.join([home, ".cache"])
end

def environment(name: String) -> Result[String]
  value = System.env(name).unwrap_or("")
  if value == ""
    return error("#{name} is not set")
  end

  return ok(value)
end

def compile(root: String, binary: String, key: String, cache: Cache) -> Result[Void]
  partial = try Path.join([cache.folder, "#{key}.#{System.pid()}-#{Time.now_ms()}#{PARTIAL_SUFFIX}"])
  published = publish(root, binary, partial, cache)
  _ = Path.remove(partial, IO_TIMEOUT_MS)
  return published
end

def publish(root: String, binary: String, partial: String, cache: Cache) -> Result[Void]
  source = try Path.join([root, "src", "main.agc"])
  done = try run(binary, ["compile", source, "-o", partial], COMPILE_TIMEOUT_MS)
  if done.status != 0
    IO.warn("#{done.stdout}#{done.stderr}".trim)
    return error("cannot compile #{source}")
  end

  moved = Path.rename(partial, cache.program, IO_TIMEOUT_MS)
  if moved.ok? or File.stat(cache.program, IO_TIMEOUT_MS).ok?
    return ok()
  end

  return error((
    "cannot publish the compiled server in #{cache.folder}: #{moved.message}; " +
    "the file system cannot move a file without replacing one, so set #{CACHE_OVERRIDE} to a folder on a local disk"
  ))
end

def stamp(cache: Cache) -> Void
  _ = File.write_text("#{cache.program}#{STAMP_SUFFIX}", "#{Time.now_ms()}", IO_TIMEOUT_MS)
end

def prune(cache: Cache, now: Int) -> Void
  no_items: List[String] = []
  for name in Dir.list(cache.folder, IO_TIMEOUT_MS).unwrap_or(no_items)
    case Path.join([cache.folder, name])
      ok(path) -> prune_entry(cache, name, path, now)
      error(_) -> next
    end
  end
end

def prune_entry(cache: Cache, name: String, path: String, now: Int) -> Void
  leftover = name.ends_with?(PARTIAL_SUFFIX) or name.starts_with?(LEFTOVER_PREFIX)
  if leftover and idle_seconds(path, now) > PARTIAL_SECONDS
    _ = Path.remove(path, IO_TIMEOUT_MS)
  end

  if name.ends_with?(PROGRAM_SUFFIX) and path != cache.program and unused_seconds(path, now) > KEEP_SECONDS
    _ = Path.remove(path, IO_TIMEOUT_MS)
    _ = Path.remove("#{path}#{STAMP_SUFFIX}", IO_TIMEOUT_MS)
  end
end

def unused_seconds(program: String, now: Int) -> Int
  case File.stat("#{program}#{STAMP_SUFFIX}", IO_TIMEOUT_MS)
    ok(info) -> return now - info.modified_seconds
    error(_) -> return idle_seconds(program, now)
  end
end

def idle_seconds(path: String, now: Int) -> Int
  case File.stat(path, IO_TIMEOUT_MS)
    ok(info) -> return now - info.modified_seconds
    error(_) -> return 0
  end
end
