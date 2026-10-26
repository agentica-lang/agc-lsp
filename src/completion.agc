## Answers completion requests with the builtins that match the word before the cursor.

import Catalog from "catalog"
import Cursor from "cursor"
import Words from "words"

FUNCTION_KIND = 3
MODULE_KIND = 9

## Returns the completion items for the word before the cursor, or an empty list when there are none.
export def answer(book: Catalog.Book, cursor: Cursor.Cursor) -> Json
  chars = cursor.chars
  if !Words.code?(chars, cursor.index) or Words.after_suffix?(chars, cursor.index)
    return none()
  end

  start = Words.word_start(chars, cursor.index)
  partial = chars.take(cursor.index).drop(start).join("")
  replaced = Cursor.range(cursor, start, cursor.index)
  if !Words.dotted?(chars, start)
    bare = functions(Catalog.bare_starting(book, partial), false, replaced)
    return JSON.array(namespaces(book, partial, replaced).concat(bare))
  end

  case Words.receiver(chars, start)
    ok(receiver) if Catalog.namespace?(book, receiver.text) ->
      return JSON.array(functions(Catalog.functions_of(book, receiver.text, partial), true, replaced))
    ok(_) -> return none()
    error(_) -> return none()
  end
end

def none() -> Json
  items: List[Json] = []
  return JSON.array(items)
end

def namespaces(book: Catalog.Book, prefix: String, replaced: Json) -> List[Json]
  return Catalog.namespaces_starting(book, prefix).map do |name|
    JSON.object({
      "label": JSON.from(name),
      "kind": JSON.from(MODULE_KIND),
      "textEdit": edit(replaced, name),
    })
  end
end

def functions(entries: List[Catalog.Entry], by_member: Bool, replaced: Json) -> List[Json]
  return entries.map do |entry| function_item(entry, by_member, replaced) end
end

def edit(replaced: Json, text: String) -> Json
  return JSON.object({"range": replaced, "newText": JSON.from(text)})
end

def function_item(entry: Catalog.Entry, by_member: Bool, replaced: Json) -> Json
  label = entry.name
  if by_member
    label = entry.member
  end

  return JSON.object({
    "label": JSON.from(label),
    "kind": JSON.from(FUNCTION_KIND),
    "detail": JSON.from(entry.signatures.join("\n")),
    "documentation": JSON.object({"kind": JSON.from("markdown"), "value": JSON.from(entry.description)}),
    "textEdit": edit(replaced, label),
  })
end
