## Answers completion requests with the builtins that match the word before the cursor.

import Catalog from "catalog"
import Cursor from "cursor"
import Words from "words"

## Returns the completion items for the word before the cursor, or an empty list when there are none.
def answer(book: Catalog.Book, cursor: Cursor.Cursor) -> JSON.Value
  chars = cursor.chars
  if !Words.code?(chars, cursor.index) or Words.after_suffix?(chars, cursor.index)
    return no_items()
  end

  start = Words.word_start(chars, cursor.index)
  partial = chars.take(cursor.index).drop(start).join("")
  replaced = Cursor.range(cursor, start, cursor.index)
  if !Words.dotted?(chars, start)
    bare = Catalog.bare_starting(book, partial)
    return JSON.array(namespaces(book, partial, bare, replaced).concat(members(bare, "", replaced)))
  end

  case Words.receiver(chars, start)
    ok(receiver) if Catalog.namespace?(book, receiver.text) ->
      return JSON.array(members(Catalog.members_of(book, receiver.text, partial), "", replaced))
    ok(receiver) ->
      return family_items(book, chars, receiver, partial, replaced)
    error(_) -> return no_items()
  end
end

private

FUNCTION_KIND = 3

MODULE_KIND = 9

TYPE_KINDS = {"struct": 22, "enum": 13, "opaque": 7}

## Offers the members of a family, as in `OpenSSL.Digest.`: the namespace is the word before the receiver, and the
## catalog names a member `Digest.sha256`.
def family_items(
  book: Catalog.Book,
  chars: List[String],
  family: Words.Word,
  partial: String,
  replaced: JSON.Value,
) -> JSON.Value
  case Words.receiver(chars, family.start)
    ok(outer) if Catalog.namespace?(book, outer.text) ->
      prefix = "#{family.text}."
      return JSON.array(members(Catalog.members_of(book, outer.text, "#{prefix}#{partial}"), prefix, replaced))
    ok(_) -> return no_items()
    error(_) -> return no_items()
  end
end

def no_items() -> JSON.Value
  items: List[JSON.Value] = []
  return JSON.array(items)
end

## Leaves out a namespace that is also a bare type, such as Process: the item of the type stands for both.
def namespaces(book: Catalog.Book, prefix: String, bare: List[Catalog.Entry], replaced: JSON.Value) -> List[JSON.Value]
  types = Set.new(bare.map do |entry| entry.name end)
  only_namespaces = Catalog.namespaces_starting(book, prefix).filter do |name| !types.include?(name) end
  return only_namespaces.map do |name|
    JSON.object({
      "label": JSON.from(name),
      "kind": JSON.from(MODULE_KIND),
      "textEdit": edit(replaced, name),
    })
  end
end

def members(entries: List[Catalog.Entry], family: String, replaced: JSON.Value) -> List[JSON.Value]
  return entries.map do |entry| member_item(entry, family, replaced) end
end

def edit(replaced: JSON.Value, text: String) -> JSON.Value
  return JSON.object({"range": replaced, "newText": JSON.from(text)})
end

## `family` is what the member name starts with and the label leaves out: "" for a bare name or a namespace member.
def member_item(entry: Catalog.Entry, family: String, replaced: JSON.Value) -> JSON.Value
  label = entry.name
  if entry.namespace != ""
    label = entry.member
  end

  label = label.slice(family.length, label.length - family.length)

  return JSON.object({
    "label": JSON.from(label),
    "kind": JSON.from(TYPE_KINDS.get(entry.kind).unwrap_or(FUNCTION_KIND)),
    "detail": JSON.from(entry.signatures.join("\n")),
    "documentation": JSON.object({"kind": JSON.from("markdown"), "value": JSON.from(entry.description)}),
    "textEdit": edit(replaced, label),
  })
end
