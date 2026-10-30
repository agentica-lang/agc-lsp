## Reads the fields of JSON objects, with a default when a field is missing or of another kind.

## Returns the text of the field, or an empty text.
export def text(found: Json, key: String) -> String
  return JSON.string(JSON.get(found, key).unwrap_or(JSON.null())).unwrap_or("")
end

## Returns the items of the list field, or an empty list.
export def items(found: Json, key: String) -> List[Json]
  no_items: List[Json] = []
  return JSON.list(JSON.get(found, key).unwrap_or(JSON.null())).unwrap_or(no_items)
end

## Returns the field, or null when it is missing.
export def value(found: Json, key: String) -> Json
  return JSON.get(found, key).unwrap_or(JSON.null())
end
