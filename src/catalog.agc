LOAD_TIMEOUT_MS = 10000

export struct Entry
  name: String
  namespace: String
  member: String
  signatures: List[String]
  description: String
end

export struct Book
  entries: Map[String, Entry]
  namespaces: Set[String]
end

export def empty() -> Book
  entries: Map[String, Entry] = {}
  namespaces: Set[String] = Set.new([])
  return Book(entries: entries, namespaces: namespaces)
end

export def load(agentica: String) -> Result[Book]
  helper = try Process.spawn_captured(agentica, ["--json", "help"], ".", LOAD_TIMEOUT_MS)
  loaded = read(helper)
  Process.close(helper)
  return loaded
end

export def parse(text: String) -> Result[Book]
  found: List[Json] = try JSON.list(try JSON.parse(text))
  book = empty()
  for item in found
    name = field(item, "name")
    if name == ""
      next
    end
    entry = entry_of(item, name)
    book = book.with(entries: book.entries.put(name, entry))
    if entry.namespace != ""
      book = book.with(namespaces: book.namespaces.add(entry.namespace))
    end
  end
  if book.entries.size == 0
    return error("the catalog has no builtins")
  end
  return ok(book)
end

export def find(book: Book, name: String) -> Result[Entry]
  return book.entries.get(name)
end

export def namespace?(book: Book, name: String) -> Bool
  return book.namespaces.include?(name)
end

export def methods_named(book: Book, member: String) -> List[Entry]
  return sorted(book.entries.keys).map do |name| book.entries.get(name).unwrap! end.filter do |entry|
    entry.namespace != "" and entry.member == member
  end
end

export def functions_of(book: Book, namespace: String, prefix: String) -> List[Entry]
  return sorted(book.entries.keys).map do |name| book.entries.get(name).unwrap! end.filter do |entry|
    entry.namespace == namespace and entry.member.starts_with?(prefix)
  end
end

export def bare_starting(book: Book, prefix: String) -> List[Entry]
  return functions_of(book, "", prefix)
end

export def namespaces_starting(book: Book, prefix: String) -> List[String]
  return sorted(book.namespaces.to_a).filter do |name| name.starts_with?(prefix) end
end

def read(helper: Process) -> Result[Book]
  try Process.close_stdin(helper, LOAD_TIMEOUT_MS)
  output = try Process.output(helper, LOAD_TIMEOUT_MS)
  status = try Process.wait(helper, LOAD_TIMEOUT_MS)
  if status != 0
    return error("agentica exited with status #{status}: #{output.stderr.strip}")
  end
  return parse(output.stdout)
end

def entry_of(item: Json, name: String) -> Entry
  namespace = ""
  member = name
  case name.index_of(".")
    ok(dot) ->
      namespace = name.slice(0, dot)
      member = name.slice(dot + 1, name.length - dot - 1)
    error(_) -> namespace = ""
  end
  return Entry(
    name: name,
    namespace: namespace,
    member: member,
    signatures: signatures_of(item),
    description: field(item, "description"),
  )
end

def signatures_of(item: Json) -> List[String]
  none: List[Json] = []
  overloads = JSON.list(JSON.get(item, "overloads").unwrap_or(JSON.null())).unwrap_or(none)
  if overloads.size == 0
    return [field(item, "signature")]
  end
  return overloads.map do |overload| field(overload, "signature") end
end

def field(item: Json, key: String) -> String
  return JSON.string(JSON.get(item, key).unwrap_or(JSON.null())).unwrap_or("")
end

def sorted(names: List[String]) -> List[String]
  return names.sort
end
