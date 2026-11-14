## Loads the catalog of Agentica builtins that `agentica --json help` prints.

## Describes a builtin function or type: its qualified name, its namespace and member, its signatures and its
## description.
struct Entry
  ## Is the qualified name, such as String.split.
  name: String
  ## Is the part before the dot, or empty for a bare function.
  namespace: String
  ## Is the part after the dot.
  member: String
  ## Is struct, enum or opaque for a type, or empty for a function.
  kind: String
  ## Lists the signatures, one for each overload; a type has one, its declaration with its fields or variants.
  signatures: List[String]
  ## Is the description of the builtin.
  description: String
end

## Holds the entries by name, in name order, and the set of namespaces.
struct Book
  ## Maps each qualified name to its entry.
  entries: Map[String, Entry]
  ## Lists the entries in name order.
  ordered: List[Entry]
  ## Lists the namespaces.
  namespaces: Set[String]
end

## Returns a catalog without entries.
def empty() -> Book
  entries: Map[String, Entry] = {}
  namespaces: Set[String] = Set.new([])
  return Book(entries: entries, ordered: [], namespaces: namespaces)
end

## Returns the catalog that the agentica binary prints, or an error when it cannot be run or read.
def load(agentica: String) -> Result[Book]
  options = Process.Options(timeout_ms: LOAD_TIMEOUT_MS, chdir: ".")
  helper = try Process.spawn_captured(agentica, ["--json", "help"], options)
  loaded = read(helper, Time.now_ms() + LOAD_TIMEOUT_MS)
  Process.close(helper)
  return loaded
end

## Returns the catalog of the JSON text of `help`, or an error when it has no builtins.
def parse(text: String) -> Result[Book]
  found: List[JSON.Value] = try JSON.list(try JSON.parse(text))
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
      some(entry) -> ordered = ordered.push(entry)
      none -> next
    end
  end

  return ok(book.with(ordered: ordered))
end

## Returns the entry of the object that `agentica --json help NAME` prints for a builtin.
def from_help(item: JSON.Value) -> Entry
  return entry_of(item, field(item, "name"))
end

## Returns the builtin with the qualified name, or an error when there is none.
def find(book: Book, name: String) -> Result[Entry]
  return book.entries.get(name).to_result("no builtin #{name}")
end

## Returns true when the entry is a type, such as File.Info, rather than a function.
def type?(entry: Entry) -> Bool
  return entry.kind != ""
end

## Returns true when the name is a namespace of builtins, such as String.
def namespace?(book: Book, name: String) -> Bool
  return book.namespaces.include?(name)
end

## Returns the namespaced builtins whose member has the name.
def methods_named(book: Book, member: String) -> List[Entry]
  return book.ordered.filter do |entry| !type?(entry) and entry.namespace != "" and entry.member == member end
end

## Returns the builtins of the namespace whose member starts with the prefix.
def members_of(book: Book, namespace: String, prefix: String) -> List[Entry]
  return book.ordered.filter do |entry| entry.namespace == namespace and entry.member.start_with?(prefix) end
end

## Returns the builtins without namespace whose name starts with the prefix.
def bare_starting(book: Book, prefix: String) -> List[Entry]
  return members_of(book, "", prefix)
end

## Returns the namespaces that start with the prefix, in order.
def namespaces_starting(book: Book, prefix: String) -> List[String]
  return book.namespaces.to_a.sort.filter do |name| name.start_with?(prefix) end
end

private

LOAD_TIMEOUT_MS = 10_000

SHORTEST_WAIT_MS = 1

def read(helper: Process, deadline: Int) -> Result[Book]
  try Process.close_stdin(helper, remaining(deadline))
  output = try Process.output(helper, remaining(deadline))
  status = try Process.wait(helper, remaining(deadline))
  if status != 0
    return error("agentica exited with status #{status}: #{output.stderr.strip}")
  end

  return parse(output.stdout)
end

def entry_of(item: JSON.Value, name: String) -> Entry
  namespace = ""
  member = name
  dot = name.index_of(".").unwrap_or(-1)
  if dot >= 0
    namespace = name.slice(0, dot)
    member = name.slice(dot + 1, name.length - dot - 1)
  end

  kind = field(item, "kind")
  signatures = signatures_of(item)
  if kind != ""
    signatures = [declaration(item, kind)]
  end

  return Entry(
    name: name,
    namespace: namespace,
    member: member,
    kind: kind,
    signatures: signatures,
    description: field(item, "description"),
  )
end

def declaration(item: JSON.Value, kind: String) -> String
  head = field(item, "signature")
  lines = case kind
    "struct" -> parts(item, "fields").flat_map do |part| documented(part, field_line(part)) end
    "enum" -> parts(item, "variants").flat_map do |part| documented(part, variant_line(part)) end
    _ -> []
  end

  if lines.size == 0
    return head
  end

  return [head].concat(lines).push("end").join("\n")
end

def parts(item: JSON.Value, key: String) -> List[JSON.Value]
  no_items: List[JSON.Value] = []
  return JSON.list(JSON.get(item, key).unwrap_or(JSON.null())).unwrap_or(no_items)
end

def documented(part: JSON.Value, line: String) -> List[String]
  doc = field(part, "doc")
  if doc == ""
    return ["  #{line}"]
  end

  return ["  ## #{doc}", "  #{line}"]
end

def field_line(part: JSON.Value) -> String
  line = "#{field(part, "name")}: #{field(part, "type")}"
  default = field(part, "default")
  if default == ""
    return line
  end

  return "#{line} = #{default}"
end

def variant_line(part: JSON.Value) -> String
  payload = parts(part, "payload").map do |type| JSON.string(type).unwrap_or("") end
  if payload.size == 0
    return field(part, "name")
  end

  return "#{field(part, "name")}(#{payload.join(", ")})"
end

def signatures_of(item: JSON.Value) -> List[String]
  overloads = parts(item, "overloads")
  if overloads.size == 0
    return [field(item, "signature")]
  end

  return overloads.map do |overload| field(overload, "signature") end
end

def field(item: JSON.Value, key: String) -> String
  return JSON.string(JSON.get(item, key).unwrap_or(JSON.null())).unwrap_or("")
end

def remaining(deadline: Int) -> Int
  left = deadline - Time.now_ms()
  if left < SHORTEST_WAIT_MS
    return SHORTEST_WAIT_MS
  end

  return left
end
