## Answers document symbol requests with the outline of the buffer, and names the kinds of symbols.

import Places from "places"
import Query from "query"

FUNCTION_KIND = 12
STRUCT_KIND = 23
ENUM_KIND = 10
CONSTANT_KIND = 14
TYPE_PARAMETER_KIND = 26
VARIABLE_KIND = 13
FIELD_KIND = 8
ENUM_MEMBER_KIND = 22
KINDS = {
  "function": FUNCTION_KIND,
  "struct": STRUCT_KIND,
  "enum": ENUM_KIND,
  "constant": CONSTANT_KIND,
  "alias": TYPE_PARAMETER_KIND,
  "field": FIELD_KIND,
  "variant": ENUM_MEMBER_KIND,
}

## Returns the document symbols of the buffer, or null when its outline cannot be had.
export def answer(agentica: String, buffer: Query.Buffer, encoding: String) -> Result[Json]
  outlined = try Query.outline_of_buffer(agentica, buffer)
  case outlined
    Query.Outlined.Refused(_) -> return ok(JSON.null())
    Query.Outlined.Found(items) -> return ok(symbols(items, buffer.text.split("\n"), encoding))
  end
end

## Returns the LSP symbol kind of a kind of declaration that agentica names, a variable for an unknown one.
export def kind_of(kind: String) -> Int
  return KINDS.get(kind).unwrap_or(VARIABLE_KIND)
end

def symbols(items: List[Query.Item], lines: List[String], encoding: String) -> Json
  return JSON.array(items.map do |item| symbol(item, lines, encoding) end)
end

def symbol(item: Query.Item, lines: List[String], encoding: String) -> Json
  fields: Map[String, Json] = {
    "name": JSON.from(item.name),
    "kind": JSON.from(kind_of(item.kind)),
    "range": Places.range(lines, item.span.start, item.span.stop, encoding),
    "selectionRange": Places.range(lines, item.name_span.start, item.name_span.stop, encoding),
  }
  if item.signature != item.name
    fields = fields.put("detail", JSON.from(item.signature))
  end
  if item.children.size > 0
    fields = fields.put("children", symbols(item.children, lines, encoding))
  end
  return JSON.object(fields)
end
