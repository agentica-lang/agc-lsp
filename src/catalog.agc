## Loads the catalog of Agentica builtins that `agentica --json help` prints.

LOAD_TIMEOUT_MS = 10_000
SHORTEST_WAIT_MS = 1

## Describes a builtin: its qualified name, its namespace and member, its signatures and its description.
export struct Entry
  ## Is the qualified name, such as String.split.
  name: String
  ## Is the part before the dot, or empty for a bare function.
  namespace: String
  ## Is the part after the dot.
  member: String
  ## Lists the signatures, one for each overload.
  signatures: List[String]
  ## Is the description of the builtin.
  description: String
end

## Holds the entries by name, in name order, and the set of namespaces.
export struct Book
  ## Maps each qualified name to its entry.
  entries: Map[String, Entry]
  ## Lists the entries in name order.
  ordered: List[Entry]
  ## Lists the namespaces.
  namespaces: Set[String]
end

## Returns a catalog without entries.
export def empty() -> Book
  entries: Map[String, Entry] = {}
  namespaces: Set[String] = Set.new([])
  return Book(entries: entries, ordered: [], namespaces: namespaces)
end

## Returns the catalog that the agentica binary prints, or an error when it cannot be run or read.
export def load(agentica: String) -> Result[Book]
  helper = try Process.spawn_captured(agentica, ["--json", "help"], ".", LOAD_TIMEOUT_MS)
  loaded = read(helper, Time.now_ms() + LOAD_TIMEOUT_MS)
  Process.close(helper)
  return loaded
end

## Returns the catalog of the JSON text of `help`, or an error when it has no builtins.
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
  ordered: List[Entry] = []
  for name in book.entries.keys.sort
    case book.entries.get(name)
      ok(entry) -> ordered = ordered.push(entry)
      error(_) -> next
    end
  end
  return ok(book.with(ordered: ordered))
end

## Returns the builtin with the qualified name, or an error when there is none.
export def find(book: Book, name: String) -> Result[Entry]
  return book.entries.get(name)
end

## Returns true when the name is a namespace of builtins, such as String.
export def namespace?(book: Book, name: String) -> Bool
  return book.namespaces.include?(name)
end

## Returns the namespaced builtins whose member has the name.
export def methods_named(book: Book, member: String) -> List[Entry]
  return book.ordered.filter do |entry| entry.namespace != "" and entry.member == member end
end

## Returns the builtins of the namespace whose member starts with the prefix.
export def functions_of(book: Book, namespace: String, prefix: String) -> List[Entry]
  return book.ordered.filter do |entry| entry.namespace == namespace and entry.member.starts_with?(prefix) end
end

## Returns the builtins without namespace whose name starts with the prefix.
export def bare_starting(book: Book, prefix: String) -> List[Entry]
  return functions_of(book, "", prefix)
end

## Returns the namespaces that start with the prefix, in order.
export def namespaces_starting(book: Book, prefix: String) -> List[String]
  return book.namespaces.to_a.sort.filter do |name| name.starts_with?(prefix) end
end

def read(helper: Process, deadline: Int) -> Result[Book]
  try Process.close_stdin(helper, remaining(deadline))
  output = try Process.output(helper, remaining(deadline))
  status = try Process.wait(helper, remaining(deadline))
  if status != 0
    return error("agentica exited with status #{status}: #{output.stderr.strip}")
  end
  return parse(output.stdout)
end

def remaining(deadline: Int) -> Int
  left = deadline - Time.now_ms()
  if left < SHORTEST_WAIT_MS
    return SHORTEST_WAIT_MS
  end
  return left
end

def entry_of(item: Json, name: String) -> Entry
  namespace = ""
  member = name
  dot = name.index_of(".").unwrap_or(-1)
  if dot >= 0
    namespace = name.slice(0, dot)
    member = name.slice(dot + 1, name.length - dot - 1)
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
