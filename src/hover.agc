import Catalog from "catalog"
import Cursor from "cursor"
import Words from "words"

struct Found
  entries: List[Catalog.Entry]
  start: Int
  stop: Int
end

export def answer(book: Catalog.Book, cursor: Cursor.Cursor) -> Json
  if !Words.code?(cursor.chars, cursor.index + 1)
    return JSON.null()
  end
  case find(book, cursor)
    ok(found) ->
      contents = JSON.object({
        "kind": JSON.from("markdown"),
        "value": JSON.from(found.entries.map do |entry| markdown(entry) end.join("\n\n---\n\n")),
      })
      return JSON.object({"contents": contents, "range": Cursor.range(cursor, found.start, found.stop)})
    error(_) -> return JSON.null()
  end
end

def find(book: Catalog.Book, cursor: Cursor.Cursor) -> Result[Found]
  chars = cursor.chars
  word = try Words.at(chars, cursor.index)
  if Words.dotted?(chars, word.start)
    return after_dot(book, chars, word)
  end
  if Catalog.namespace?(book, word.text)
    return qualified(book, word.text, try Words.member(chars, word.stop), word.start)
  end
  if !Words.called?(chars, word.stop)
    return error("not a call")
  end
  entry = try Catalog.find(book, word.text)
  return ok(Found(entries: [entry], start: word.start, stop: word.stop))
end

def after_dot(book: Catalog.Book, chars: List[String], word: Words.Word) -> Result[Found]
  receiver = Words.receiver(chars, word.start)
  if receiver.ok? and Catalog.namespace?(book, receiver.unwrap!.text)
    return qualified(book, receiver.unwrap!.text, word, receiver.unwrap!.start)
  end
  if receiver.ok? and Words.type_name?(receiver.unwrap!.text)
    return error("a capitalized receiver is not a value")
  end
  entries = Catalog.methods_named(book, word.text)
  if entries.size == 0
    return error("no builtin method #{word.text}")
  end
  return ok(Found(entries: entries, start: word.start, stop: word.stop))
end

def qualified(book: Catalog.Book, namespace: String, member: Words.Word, start: Int) -> Result[Found]
  entry = try Catalog.find(book, "#{namespace}.#{member.text}")
  return ok(Found(entries: [entry], start: start, stop: member.stop))
end

def markdown(entry: Catalog.Entry) -> String
  signatures = entry.signatures.map do |signature| "```agc\n#{signature}\n```" end
  return "#{signatures.join("\n")}\n\n#{entry.description}"
end
