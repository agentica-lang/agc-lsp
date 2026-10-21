## Asks agentica for the type and the definition at a position, and for the outline of a file.

import Catalog from "catalog"
import Fields from "fields"
import Places from "places"
import Proc from "proc"
import Logger from "std/logger"
import Uri from "uri"

QUERY_TIMEOUT_MS = 10_000
EXPECTED_CODES = ["LEX-", "PARSE-", "CHECK-", "QUERY-NO-EXPRESSION"]

## Holds the text of a file as the editor shows it, and the path it stands for.
export struct Buffer
  ## Is the absolute path of the file.
  path: String
  ## Is the text of the buffer.
  text: String
end

## Holds a declaration that a name refers to: a function, struct, enum, variant, field, constant or local.
export struct Declaration
  ## Is the kind: function, struct, enum, variant, field, constant, local, parameter, loop or pattern.
  kind: String
  ## Is the signature, written as agentica writes it.
  signature: String
  ## Is the text of the `##` doc, or empty when there is none.
  doc: String
  ## Is the place of the name, in a file with an absolute path.
  name_span: Places.Span
end

## Tells what a name refers to.
export enum Origin
  ## Is a name without declaration.
  Unknown
  ## Is a declaration of the program.
  Declared(Declaration)
  ## Is a builtin, with its entry of the catalog.
  Builtin(Catalog.Entry)
end

## Holds the expression at a position: its source, its type and where its name is declared.
export struct Subject
  ## Is the source text of the expression.
  text: String
  ## Is the type of the expression, written as agentica writes it.
  type: String
  ## Is the place of the whole expression, in the file that was asked.
  span: Places.Span
  ## Tells what the name of the expression refers to.
  origin: Origin
end

## Holds a declaration of a file, or a field or a variant of one.
export struct Item
  ## Is the kind: function, struct, enum, alias, constant, field or variant.
  kind: String
  ## Is the name.
  name: String
  ## Is the signature, written as agentica writes it.
  signature: String
  ## Is the whole declaration.
  span: Places.Span
  ## Is the name alone.
  name_span: Places.Span
  ## Lists the fields of a struct or the variants of an enum.
  children: List[Item]
end

## Is what a query of the type gives.
export enum Typed
  ## Is the code of the diagnostic that agentica gave instead of a type.
  Refused(String)
  ## Is the expression at the position.
  Found(Subject)
end

## Is what a query of the outline gives.
export enum Outlined
  ## Is the code of the diagnostic that agentica gave instead of an outline.
  Refused(String)
  ## Lists the declarations of the file.
  Found(List[Item])
end

enum Reply
  Answer(Json)
  Refusal(String)
end

## Returns the expression at a line and a column of the buffer, both counted from 1 in code points.
export def type_at(agentica: String, buffer: Buffer, line: Int, column: Int) -> Result[Typed]
  folder = Uri.folder_of(buffer.path)
  arguments = ["--json", "type-at", "--partial", "--stdin", "#{buffer.path}:#{line}:#{column}"]
  reply = try ask(agentica, folder, arguments, buffer.text)
  case reply
    Reply.Refusal(code) -> return ok(Typed.Refused(code))
    Reply.Answer(found) -> return ok(Typed.Found(subject_of(found, folder)))
  end
end

## Returns the declarations of the buffer.
export def outline_of_buffer(agentica: String, buffer: Buffer) -> Result[Outlined]
  arguments = ["--json", "outline", "--stdin", buffer.path]
  reply = try ask(agentica, Uri.folder_of(buffer.path), arguments, buffer.text)
  return outlined(reply)
end

def outlined(reply: Reply) -> Result[Outlined]
  case reply
    Reply.Refusal(code) -> return ok(Outlined.Refused(code))
    Reply.Answer(found) -> return ok(Outlined.Found(Fields.items(found, "items").map do |item| item_of(item) end))
  end
end

def ask(agentica: String, folder: String, arguments: List[String], text: String) -> Result[Reply]
  deadline = Time.now_ms() + QUERY_TIMEOUT_MS
  output = try Proc.run(agentica, arguments, text, deadline, folder)
  if output.status == 0
    if output.unsent != ""
      return error(output.unsent)
    end
    return ok(Reply.Answer(try JSON.parse(output.stdout)))
  end
  code = refusal_code(output.stderr)
  if code == ""
    return error("agentica exited with status #{output.status}: #{output.stderr.strip}")
  end
  return ok(Reply.Refusal(code))
end

def refusal_code(stderr: String) -> String
  lines = stderr.strip.split("\n")
  case JSON.parse(lines[lines.size - 1])
    ok(found) ->
      code = Fields.text(found, "code")
      if expected?(code)
        Logger.debug("agentica refused the query: #{code}")
        return code
      end
      return ""
    error(_) -> return ""
  end
end

def expected?(code: String) -> Bool
  return EXPECTED_CODES.any? do |prefix| code.starts_with?(prefix) end
end

def subject_of(found: Json, folder: String) -> Subject
  return Subject(
    text: Fields.text(found, "text"),
    type: Fields.text(found, "type"),
    span: located(Places.span(Fields.value(found, "span")), folder),
    origin: origin_of(found, folder),
  )
end

def origin_of(found: Json, folder: String) -> Origin
  definition = Fields.value(found, "definition")
  if JSON.kind(definition) == "object"
    return Origin.Declared(Declaration(
      kind: Fields.text(definition, "kind"),
      signature: Fields.text(definition, "signature"),
      doc: Fields.text(definition, "doc"),
      name_span: located(Places.span(Fields.value(definition, "name_span")), folder),
    ))
  end
  help = Fields.value(found, "help")
  if Fields.text(found, "kind") == "builtin" and JSON.kind(help) == "object"
    return Origin.Builtin(Catalog.from_help(help))
  end
  return Origin.Unknown
end

def located(span: Places.Span, folder: String) -> Places.Span
  return span.with(file: Uri.resolve(folder, span.file))
end

def item_of(found: Json) -> Item
  children = Fields.items(found, "fields").map do |field| field_of(field) end
  children = children.concat(Fields.items(found, "variants").map do |variant| variant_of(variant) end)
  return Item(
    kind: Fields.text(found, "kind"),
    name: Fields.text(found, "name"),
    signature: Fields.text(found, "signature"),
    span: Places.span(Fields.value(found, "span")),
    name_span: Places.span(Fields.value(found, "name_span")),
    children: children,
  )
end

def field_of(found: Json) -> Item
  name = Fields.text(found, "name")
  name_span = Places.span(Fields.value(found, "name_span"))
  return Item(
    kind: "field",
    name: name,
    signature: "#{name}: #{Fields.text(found, "type")}",
    span: name_span,
    name_span: name_span,
    children: [],
  )
end

def variant_of(found: Json) -> Item
  name = Fields.text(found, "name")
  name_span = Places.span(Fields.value(found, "name_span"))
  payload = Fields.items(found, "payload").map do |type| JSON.string(type).unwrap_or("") end
  signature = name
  if payload.size > 0
    signature = "#{name}(#{payload.join(", ")})"
  end
  return Item(
    kind: "variant",
    name: name,
    signature: signature,
    span: name_span,
    name_span: name_span,
    children: [],
  )
end
