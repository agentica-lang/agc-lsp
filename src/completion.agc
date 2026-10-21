import Catalog from "catalog"
import Cursor from "cursor"
import Words from "words"

FUNCTION_KIND = 3
MODULE_KIND = 9

export def answer(book: Catalog.Book, cursor: Cursor.Cursor) -> Json
  chars = cursor.chars
  if !Words.code?(chars, cursor.index)
    return none()
  end
  start = Words.word_start(chars, cursor.index)
  partial = chars.take(cursor.index).drop(start).join("")
  if !Words.dotted?(chars, start)
    return JSON.array(namespaces(book, partial).concat(functions(Catalog.bare_starting(book, partial), false)))
  end
  receiver = Words.receiver(chars, start)
  if receiver.ok? and Catalog.namespace?(book, receiver.unwrap!.text)
    return JSON.array(functions(Catalog.functions_of(book, receiver.unwrap!.text, partial), true))
  end
  return none()
end

def none() -> Json
  items: List[Json] = []
  return JSON.array(items)
end

def namespaces(book: Catalog.Book, prefix: String) -> List[Json]
  return Catalog.namespaces_starting(book, prefix).map do |name|
    JSON.object({"label": JSON.from(name), "kind": JSON.from(MODULE_KIND)})
  end
end

def functions(entries: List[Catalog.Entry], by_member: Bool) -> List[Json]
  return entries.map do |entry| function_item(entry, by_member) end
end

def function_item(entry: Catalog.Entry, by_member: Bool) -> Json
  label = entry.name
  if by_member
    label = entry.member
  end
  return JSON.object({
    "label": JSON.from(label),
    "kind": JSON.from(FUNCTION_KIND),
    "detail": JSON.from(entry.signatures.join("\n")),
    "documentation": JSON.from(entry.description),
  })
end
