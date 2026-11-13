## Reads the fields of JSON objects, with a default when a field is missing or of another kind.

## Returns the text of the field, or an empty text.
def text(found: JSON.Value, key: String) -> String
  return JSON.string(JSON.get(found, key).unwrap_or(JSON.null())).unwrap_or("")
end

## Returns the items of the list field, or an empty list.
def items(found: JSON.Value, key: String) -> List[JSON.Value]
  no_items: List[JSON.Value] = []
  return JSON.list(JSON.get(found, key).unwrap_or(JSON.null())).unwrap_or(no_items)
end

## Returns the field, or null when it is missing.
def value(found: JSON.Value, key: String) -> JSON.Value
  return JSON.get(found, key).unwrap_or(JSON.null())
end
