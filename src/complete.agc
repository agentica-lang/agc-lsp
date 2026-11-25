## Answers completion requests with the builtins and with the names of the program: its declarations, the names of the
## function that the cursor is in, the fields and variants of a type, the methods of a value, the names of a module and
## the modules and files that an import can name.

import Catalog from "catalog"
import Completion from "completion"
import Cursor from "cursor"
import Lookup from "lookup"
import Places from "places"
import Probe from "probe"
import Analysis from "std/analysis"
import Uri from "uri"
import Words from "words"

## Returns the completion items for the word before the cursor, or an empty list when there are none.
def answer(request: Lookup.Request) -> Result[JSON.Value]
  named = try names(request)
  if imported_module(request.cursor).some?
    return ok(JSON.array(named))
  end

  return ok(JSON.array(named.concat(Completion.items(request.book, request.cursor))))
end

private

STD_MODULES = [
  "actor", "analysis", "archive", "bdd", "binary", "cache", "cookie", "eag", "heap", "html", "http", "logger", "mime",
  "option_parser", "queue", "regex", "supervisor", "toml", "uri", "utc",
]

KINDS = {
  "function": 3,
  "struct": 22,
  "enum": 13,
  "alias": 25,
  "constant": 21,
  "resource": 22,
  "module": 9,
}

FUNCTION_KIND = 3

STRUCT_KIND = 22

METHOD_KIND = 2

FIELD_KIND = 5

VARIABLE_KIND = 6

MODULE_KIND = 9

FILE_KIND = 17

FOLDER_KIND = 19

VARIANT_KIND = 20

READ_TIMEOUT_MS = 10_000

AGENTICA_EXTENSION = ".agc"

SKIPPED_FOLDERS = Set.new(["_build", "node_modules", "deps"])

MAX_PATHS = 200

def names(request: Lookup.Request) -> Result[List[JSON.Value]]
  cursor = request.cursor
  chars = cursor.chars
  if !Words.code?(chars, cursor.index)
    return ok(import_paths(request))
  elsif Words.after_suffix?(chars, cursor.index)
    return ok([])
  end

  start = Words.word_start(chars, cursor.index)
  partial = chars.take(cursor.index).drop(start).join("")
  replaced = Cursor.range(cursor, start, cursor.index)
  if Words.dotted?(chars, start)
    return members(request, start, partial, replaced)
  end

  case imported_module(cursor)
    some(module) -> return ok(exports(request, module, partial, replaced))
    none -> return scope(request, partial, replaced)
  end
end

def kind_of(kind: String) -> Int
  return KINDS.get(kind).unwrap_or(FUNCTION_KIND)
end

## Returns the std modules and the files that the path of an import can name, while the cursor is in its quotes.
def import_paths(request: Lookup.Request) -> List[JSON.Value]
  chars = request.cursor.chars
  opening = last_quote(chars, request.cursor.index)
  if opening < 0 or !chars.take(opening).join("").strip.end_with?("from") or !import_line?(chars)
    return []
  end

  partial = chars.take(request.cursor.index).drop(opening + 1).join("")
  replaced = Cursor.range(request.cursor, opening + 1, request.cursor.index)
  found: List[JSON.Value] = []
  for name in STD_MODULES
    path = "std/#{name}"
    if path.start_with?(partial)
      found = found.push(Completion.item(path, MODULE_KIND, "", "", replaced))
    end
  end

  return found.concat(project_paths(request, partial, replaced))
end

def import_line?(chars: List[String]) -> Bool
  text = chars.join("").strip
  return text.start_with?("import") or text.start_with?("}")
end

def last_quote(chars: List[String], upto: Int) -> Int
  index = upto - 1
  while index >= 0
    if chars[index] == "\""
      return index
    end

    index -= 1
  end

  return -1
end

def project_paths(request: Lookup.Request, partial: String, replaced: JSON.Value) -> List[JSON.Value]
  slash = partial.length
  while slash > 0 and partial.at(slash - 1) != "/"
    slash -= 1
  end

  folder_part = partial.slice(0, slash)
  name_part = partial.slice(slash, partial.length - slash)
  folder = Uri.collapsed(Uri.resolve(Uri.folder_of(request.path), folder_part))
  found: List[JSON.Value] = []
  if !Uri.inside?(bound(request), folder)
    return found
  end

  case Dir.list(folder, READ_TIMEOUT_MS)
    ok(listed) ->
      for name in listed.sort.take(MAX_PATHS)
        if !name.start_with?(name_part) or (name.start_with?(".") and !name_part.start_with?("."))
          next
        end

        if name.end_with?(AGENTICA_EXTENSION)
          stem = name.slice(0, name.length - AGENTICA_EXTENSION.length)
          if !Uri.same_path?("#{folder}/#{name}", request.path)
            found = found.push(Completion.item("#{folder_part}#{stem}", FILE_KIND, "", "", replaced))
          end
        elsif !SKIPPED_FOLDERS.include?(name) and directory?("#{folder}/#{name}")
          found = found.push(Completion.item("#{folder_part}#{name}/", FOLDER_KIND, "", "", replaced))
        end
      end

    error(_) -> return found
  end

  return found
end

## Returns the folder that an import path can reach: the workspace, or the folder of the file when there is none.
def bound(request: Lookup.Request) -> String
  if request.root == ""
    return Uri.folder_of(request.path)
  end

  return request.root
end

def directory?(path: String) -> Bool
  case File.stat(path, READ_TIMEOUT_MS)
    ok(info) -> return info.kind == "directory"
    error(_) -> return false
  end
end

## Returns the module path of the import whose list of names the cursor is in, as `import {a, |} from "lib"`.
def imported_module(cursor: Cursor.Cursor) -> Optional[String]
  before = cursor.chars.take(cursor.index).join("")
  after = cursor.chars.drop(cursor.index).join("")
  if !before.strip.start_with?("import") or !before.include?("{") or before.include?("}")
    return none
  end

  marker = "} from \""
  at = after.index_of(marker).unwrap_or(-1)
  if at < 0
    return none
  end

  rest = after.slice(at + marker.length, after.length - at - marker.length)
  closing = rest.index_of("\"").unwrap_or(-1)
  if closing < 0
    return none
  end

  return some(rest.slice(0, closing))
end

def module_path(request: Lookup.Request, module: String) -> String
  if module.start_with?("std/")
    return module
  end

  return Uri.resolve(Uri.folder_of(request.path), "#{module}.agc")
end

def exports(request: Lookup.Request, module: String, partial: String, replaced: JSON.Value) -> List[JSON.Value]
  case Analysis.outline(request.session, module_path(request, module))
    ok(outlined) -> return declared(outlined.items.filter do |item| item.exported end, partial, replaced)
    error(_) -> return []
  end
end

def declared(items: List[Analysis.Item], partial: String, replaced: JSON.Value) -> List[JSON.Value]
  shown = items.filter do |item| item.name.start_with?(partial) end
  return shown.map do |item|
    Completion.item(item.name, kind_of(item.kind), item.signature, item.doc, replaced)
  end
end

## Returns what the cursor can name: the declarations of the file, the names that its imports bring in and the names
## of the function it is in.
def scope(request: Lookup.Request, partial: String, replaced: JSON.Value) -> Result[List[JSON.Value]]
  case try Probe.outline(request, request.cursor.index)
    some(outlined) ->
      own = declared(outlined.items, partial, replaced)
      brought = imports(outlined, partial, replaced)
      return ok(own.concat(brought).concat(locals(request, outlined, partial, replaced)))
    none -> return ok([])
  end
end

def imports(outlined: Analysis.Outline, partial: String, replaced: JSON.Value) -> List[JSON.Value]
  found: List[JSON.Value] = []
  for imported in outlined.imports
    if imported.alias != "" and imported.alias.start_with?(partial)
      found = found.push(Completion.item(imported.alias, MODULE_KIND, "import #{imported.path}", "", replaced))
    end

    for entry in imported.names
      if entry.local.start_with?(partial)
        kind = imported_kind(entry.local)
        found = found.push(Completion.item(entry.local, kind, "from #{imported.path}", "", replaced))
      end
    end
  end

  return found
end

def imported_kind(name: String) -> Int
  if Words.type_name?(name)
    return STRUCT_KIND
  end

  return FUNCTION_KIND
end

def locals(
  request: Lookup.Request,
  outlined: Analysis.Outline,
  partial: String,
  replaced: JSON.Value,
) -> List[JSON.Value]
  line = request.cursor.line + 1
  inside = outlined.items.filter do |item|
    item.kind == "function" and item.range.start.line <= line and line <= item.range.stop.line
  end

  if inside.size == 0
    return []
  end

  function = inside[0]
  typed: Map[String, String] = {}
  for parameter in function.parameters
    typed = typed.put(parameter.name, parameter.type)
  end

  lines = Places.lines_of(request.documents, request.path)
  for number in function.range.start.line...line
    for name in assigned(lines[number - 1])
      if typed.get(name).none?
        typed = typed.put(name, "")
      end
    end
  end

  found: List[JSON.Value] = []
  for name in typed.keys.sort
    if name.start_with?(partial)
      found = found.push(Completion.item(name, VARIABLE_KIND, typed.get(name).unwrap_or(""), "", replaced))
    end
  end

  return found
end

## Returns the names that a line of a function binds: the one of an assignment and the ones of a `for`.
def assigned(text: String) -> List[String]
  trimmed = text.strip
  if trimmed.start_with?("for ")
    head = trimmed.slice(4, trimmed.length - 4)
    stop = head.index_of(" in ").unwrap_or(-1)
    if stop < 0
      return []
    end

    parts = head.slice(0, stop).split(",").map do |part| part.strip end
    return parts.filter do |part| plain_name?(part) end
  end

  chars = trimmed.split("")
  case Words.at(chars, 0)
    ok(word) if !Words.keyword?(word.text) and !Words.type_name?(word.text) ->
      rest = chars.drop(word.stop).join("").strip
      binds = rest.start_with?("=") and !rest.start_with?("==")
      if binds or (rest.start_with?(":") and rest.include?(" = "))
        return [word.text]
      end

      return []
    ok(_) -> return []
    error(_) -> return []
  end
end

def plain_name?(text: String) -> Bool
  case Words.at(text.split(""), 0)
    ok(word) -> return word.stop == text.length and !Words.keyword?(word.text)
    error(_) -> return false
  end
end

def members(
  request: Lookup.Request,
  start: Int,
  partial: String,
  replaced: JSON.Value,
) -> Result[List[JSON.Value]]
  chars = request.cursor.chars
  safe = Words.safe?(chars, start)
  keep = Words.dot_start(chars, start)
  case Words.receiver(chars, start)
    ok(receiver) if Catalog.namespace?(request.book, receiver.text) -> return ok([])
    ok(receiver) -> return named_members(request, receiver, safe, keep, partial, replaced)
    error(_) ->
      if keep >= 1 and (chars[keep - 1] == ")" or chars[keep - 1] == "]")
        return value_members(request, keep - 1, safe, keep, partial, replaced)
      end

      return ok([])
  end
end

def named_members(
  request: Lookup.Request,
  receiver: Words.Word,
  safe: Bool,
  keep: Int,
  partial: String,
  replaced: JSON.Value,
) -> Result[List[JSON.Value]]
  case try Probe.outline(request, keep)
    some(outlined) ->
      modules = outlined.imports.filter do |imported| imported.alias == receiver.text end
      if safe and (modules.size > 0 or Words.type_name?(receiver.text))
        return ok([])
      elsif modules.size > 0
        return ok(exports(request, modules[0].path, partial, replaced))
      elsif Words.type_name?(receiver.text)
        return ok(variants(request, outlined, receiver.text, partial, replaced))
      end

      return value_members(request, receiver.stop - 1, safe, keep, partial, replaced)
    none -> return ok([])
  end
end

## The members of the value that ends at the index `last`. After `&.` they are those of the type inside its Optional.
def value_members(
  request: Lookup.Request,
  last: Int,
  safe: Bool,
  keep: Int,
  partial: String,
  replaced: JSON.Value,
) -> Result[List[JSON.Value]]
  case try Probe.type_at(request, last, keep)
    some(found) if safe ->
      case Probe.inside_optional(found.type)
        some(inner) -> return typed_members(request, inner, keep, partial, replaced)
        none -> return ok([])
      end

    some(found) -> return typed_members(request, found.type, keep, partial, replaced)
    none -> return ok([])
  end
end

def typed_members(
  request: Lookup.Request,
  type: String,
  keep: Int,
  partial: String,
  replaced: JSON.Value,
) -> Result[List[JSON.Value]]
  head = type.split("[")[0].strip
  methods = Catalog.members_of(request.book, head, partial).filter do |entry| entry.methods.size > 0 end
  found = methods.map do |entry|
    Completion.item(entry.member, METHOD_KIND, entry.methods.join("\n"), entry.description, replaced)
  end

  if found.size > 0
    return ok(found)
  end

  case try Probe.outline(request, keep)
    some(outlined) ->
      case try find_type(request, outlined, head, "struct")
        some(item) ->
          fields = item.fields.filter do |field| field.name.start_with?(partial) end
          return ok(fields.map do |field| Completion.item(field.name, FIELD_KIND, field.type, field.doc, replaced) end)
        none -> return ok([])
      end

    none -> return ok([])
  end
end

def variants(
  request: Lookup.Request,
  outlined: Analysis.Outline,
  name: String,
  partial: String,
  replaced: JSON.Value,
) -> List[JSON.Value]
  nothing: Optional[Analysis.Item] = none
  declared_enum = find_type(request, outlined, name, "enum").unwrap_or(nothing)
  case declared_enum
    some(item) ->
      shown = item.variants.filter do |variant| variant.name.start_with?(partial) end
      return shown.map do |variant|
        Completion.item(variant.name, VARIANT_KIND, payload(variant), variant.doc, replaced)
      end

    none -> return []
  end
end

def payload(variant: Analysis.Variant) -> String
  if variant.payload.size == 0
    return ""
  end

  return "(#{variant.payload.join(", ")})"
end

## Returns the struct or the enum of the name that the file declares or imports by name.
def find_type(
  request: Lookup.Request,
  outlined: Analysis.Outline,
  name: String,
  kind: String,
) -> Result[Optional[Analysis.Item]]
  here = outlined.items.filter do |item| item.kind == kind and item.name == name end
  if here.size > 0
    return ok(some(here[0]))
  end

  for imported in outlined.imports
    for entry in imported.names
      if entry.local == name
        case Analysis.outline(request.session, module_path(request, imported.path))
          ok(found) ->
            there = found.items.filter do |item| item.kind == kind and item.name == entry.name and item.exported end
            if there.size > 0
              return ok(some(there[0]))
            end

          error(_) -> next
        end
      end
    end
  end

  return ok(none)
end
