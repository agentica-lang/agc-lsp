## Answers signatureHelp requests with the signature of the function that the cursor is calling and the parameter it
## is on.

import Catalog from "catalog"
import Lookup from "lookup"
import Probe from "probe"
import Typing from "typing"
import Words from "words"

## Returns the signatures of the function that the cursor is calling, or null when it is in no call or the function is
## not known.
def answer(request: Lookup.Request) -> Result[JSON.Value]
  chars = request.cursor.chars
  case call_at(chars, request.cursor.index)
    some(call) ->
      forms = try forms_of(request, call)
      if forms.size == 0
        return ok(JSON.null())
      end

      return ok(help(forms, call.frame, request.cursor.index, chars))
    none -> return ok(JSON.null())
  end
end

private

## Holds the call that the cursor is in: its bracket and the name that is called.
struct Call
  frame: Typing.Frame
  name: Words.Word
end

struct Form
  label: String
  parameters: List[String]
  documentation: String
end

def call_at(chars: List[String], index: Int) -> Optional[Call]
  calls = Typing.frames(chars, index).filter do |frame| frame.bracket == "(" end
  if calls.size == 0 or !Words.code?(chars, index)
    return none
  end

  frame = calls[calls.size - 1]
  if frame.open == 0
    return none
  end

  case Words.at(chars, frame.open - 1)
    ok(word) if word.stop == frame.open and !Words.keyword?(word.text) and !defined?(chars, word) ->
      return some(Call(frame: frame, name: word))
    ok(_) -> return none
    error(_) -> return none
  end
end

def defined?(chars: List[String], word: Words.Word) -> Bool
  return chars.take(word.start).join("").strip == "def"
end

def forms_of(request: Lookup.Request, call: Call) -> Result[List[Form]]
  asked = try Probe.type_at(request, call.name.start, call.frame.open + 1)
  case asked
    some(found) if found.definition.size > 0 ->
      declared = found.definition[0]
      if declared.kind == "function"
        return ok([form_of(declared.signature, declared.doc)])
      end

      return ok([])
    some(found) if JSON.kind(found.help) == "object" ->
      return ok(builtin_forms(request, call, Catalog.from_help(found.help)))
    some(_) -> return ok([])
    none -> return cataloged(request, call)
  end
end

def cataloged(request: Lookup.Request, call: Call) -> Result[List[Form]]
  book = request.book
  case Words.receiver(request.cursor.chars, call.name.start)
    ok(receiver) if Catalog.namespace?(book, receiver.text) ->
      case Catalog.find(book, "#{receiver.text}.#{call.name.text}")
        ok(entry) -> return ok(builtin_forms(request, call, entry))
        error(_) -> return ok([])
      end

    ok(receiver) -> return of_receiver(request, call, receiver)
    error(_) ->
      case Catalog.find(book, call.name.text)
        ok(entry) -> return ok(builtin_forms(request, call, entry))
        error(_) -> return ok([])
      end
  end
end

## The method of the type of the receiver, which the call being typed hides from the compiler, or else every method
## of the name.
def of_receiver(request: Lookup.Request, call: Call, receiver: Words.Word) -> Result[List[Form]]
  asked = try Probe.type_at(request, receiver.stop - 1, call.name.start - 1)
  case asked
    some(found) ->
      head = found.type.split("[")[0].strip
      case Catalog.find(request.book, "#{head}.#{call.name.text}")
        ok(entry) -> return ok(builtin_forms(request, call, entry))
        error(_) -> return ok(every_method(request, call))
      end

    none -> return ok(every_method(request, call))
  end
end

def every_method(request: Lookup.Request, call: Call) -> List[Form]
  entries = Catalog.methods_named(request.book, call.name.text)
  return entries.flat_map do |entry| builtin_forms(request, call, entry) end
end

def builtin_forms(request: Lookup.Request, call: Call, entry: Catalog.Entry) -> List[Form]
  signatures = entry.signatures
  if method_call?(request, call) and entry.methods.size > 0
    signatures = entry.methods
  end

  return signatures.map do |signature| form_of(signature, entry.description) end
end

def method_call?(request: Lookup.Request, call: Call) -> Bool
  case Words.receiver(request.cursor.chars, call.name.start)
    ok(receiver) -> return !Catalog.namespace?(request.book, receiver.text)
    error(_) -> return false
  end
end

def form_of(signature: String, documentation: String) -> Form
  return Form(label: signature, parameters: parameters_of(signature), documentation: documentation)
end

## Returns the parameters of a signature as they are written in it, split at the commas that are not inside a bracket
## or a string.
def parameters_of(signature: String) -> List[String]
  chars = signature.split("")
  first = signature.index_of("(").unwrap_or(-1)
  if first < 0
    return []
  end

  found: List[String] = []
  depth = 0
  in_string = false
  start = first + 1
  index = start
  while index < chars.size
    char = chars[index]
    if in_string and char == "\\"
      index += 1
    elsif in_string
      in_string = char != "\""
    elsif char == "\""
      in_string = true
    elsif char == "(" or char == "[" or char == "{"
      depth += 1
    elsif (char == ")" or char == "]" or char == "}") and depth == 0
      found = found.push(chars.take(index).drop(start).join("").strip)
      break
    elsif char == ")" or char == "]" or char == "}"
      depth -= 1
    elsif char == "," and depth == 0
      found = found.push(chars.take(index).drop(start).join("").strip)
      start = index + 1
    end

    index += 1
  end

  return found.filter do |parameter| parameter != "" end
end

def help(forms: List[Form], frame: Typing.Frame, index: Int, chars: List[String]) -> JSON.Value
  active = active_parameter(forms[0], frame, index, chars)
  shown = forms.map do |form| form_json(form) end
  return JSON.object({
    "signatures": JSON.array(shown),
    "activeSignature": JSON.from(fitting(forms, active)),
    "activeParameter": JSON.from(active),
  })
end

def form_json(form: Form) -> JSON.Value
  parameters = form.parameters.map do |parameter| JSON.object({"label": JSON.from(parameter)}) end
  return JSON.object({
    "label": JSON.from(form.label),
    "documentation": JSON.object({"kind": JSON.from("markdown"), "value": JSON.from(form.documentation)}),
    "parameters": JSON.array(parameters),
  })
end

## Returns the index of the first form that has a parameter at the position.
def fitting(forms: List[Form], active: Int) -> Int
  for index in 0...forms.size
    if forms[index].parameters.size > active
      return index
    end
  end

  return 0
end

## Returns the parameter that the cursor is on: the one that an argument written `name:` names, or else the one that
## the commas before the cursor count.
def active_parameter(form: Form, frame: Typing.Frame, index: Int, chars: List[String]) -> Int
  written = chars.take(index).drop(frame.segment).join("").strip
  colon = written.index_of(":").unwrap_or(-1)
  if colon > 0
    named = written.slice(0, colon).strip
    for position in 0...form.parameters.size
      if form.parameters[position].start_with?("#{named}:")
        return position
      end
    end
  end

  return frame.commas
end
