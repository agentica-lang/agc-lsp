## Answers document symbol requests with the outline of the buffer, and names the kinds of symbols.

import Lookup from "lookup"
import Places from "places"
import Refusals from "refusals"
import Analysis from "std/analysis"

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
export def answer(request: Lookup.Request) -> Result[Json]
  case Analysis.outline(request.session, request.path)
    ok(outlined) ->
      lines = Places.lines_of(request.documents, request.path)
      return ok(JSON.array(outlined.items.map do |item| symbol(item, lines, request.cursor.encoding) end))
    error(message) if Refusals.at_position?(message) -> return ok(JSON.null())
    error(message) -> return error(message)
  end
end

## Returns the LSP symbol kind of a kind of declaration that agentica names, a variable for an unknown one.
export def kind_of(kind: String) -> Int
  return KINDS.get(kind).unwrap_or(VARIABLE_KIND)
end

def symbol(item: Analysis.Item, lines: List[String], encoding: String) -> Json
  children = item.fields.map do |field| field_symbol(field, lines, encoding) end
  children = children.concat(item.variants.map do |variant| variant_symbol(variant, lines, encoding) end)
  fields: Map[String, Json] = {
    "name": JSON.from(item.name),
    "kind": JSON.from(kind_of(item.kind)),
    "range": Places.range(lines, item.range, encoding),
    "selectionRange": Places.range(lines, item.name_range, encoding),
  }
  if item.signature != item.name
    fields = fields.put("detail", JSON.from(item.signature))
  end

  if children.size > 0
    fields = fields.put("children", JSON.array(children))
  end

  return JSON.object(fields)
end

def field_symbol(field: Analysis.Field, lines: List[String], encoding: String) -> Json
  return member(field.name, "field", "#{field.name}: #{field.type}", field.name_range, lines, encoding)
end

def variant_symbol(variant: Analysis.Variant, lines: List[String], encoding: String) -> Json
  signature = variant.name
  if variant.payload.size > 0
    signature = "#{variant.name}(#{variant.payload.join(", ")})"
  end

  return member(variant.name, "variant", signature, variant.name_range, lines, encoding)
end

def member(
  name: String,
  kind: String,
  signature: String,
  name_range: Analysis.Region,
  lines: List[String],
  encoding: String,
) -> Json
  fields: Map[String, Json] = {
    "name": JSON.from(name),
    "kind": JSON.from(kind_of(kind)),
    "range": Places.range(lines, name_range, encoding),
    "selectionRange": Places.range(lines, name_range, encoding),
  }
  if signature != name
    fields = fields.put("detail", JSON.from(signature))
  end

  return JSON.object(fields)
end
