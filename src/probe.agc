## Asks std/analysis about a buffer that the editor left in the middle of typing: when the buffer does not parse, the
## question goes to the buffer with the line of the cursor cut and its open brackets closed.

import Lookup from "lookup"
import Refusals from "refusals"
import Analysis from "std/analysis"
import Typing from "typing"

## Returns the answer about the character index of the cursor line, or none when the buffer and its repair give no
## answer. `keep` is how many characters of the line the repair keeps.
def type_at(request: Lookup.Request, index: Int, keep: Int) -> Result[Optional[Analysis.TypeAt]]
  line = request.cursor.line + 1
  first = Analysis.type_at_partial(request.session, request.path, line, index + 1)
  case first
    ok(found) -> return ok(some(found))
    error(failure) -> try tolerated(failure)
  end

  second = Analysis.type_at_partial(repaired(request, keep), request.path, line, index + 1)
  case second
    ok(found) -> return ok(some(found))
    error(failure) ->
      try tolerated(failure)
      return ok(none)
  end
end

## Returns the outline of the buffer, or of its repair, or none when neither can be read.
def outline(request: Lookup.Request, keep: Int) -> Result[Optional[Analysis.Outline]]
  first = Analysis.outline(request.session, request.path)
  case first
    ok(found) -> return ok(some(found))
    error(failure) -> try tolerated(failure)
  end

  second = Analysis.outline(repaired(request, keep), request.path)
  case second
    ok(found) -> return ok(some(found))
    error(failure) ->
      try tolerated(failure)
      return ok(none)
  end
end

private

def tolerated(failure: Error) -> Result[Void]
  if Refusals.at_position?(failure.message)
    return ok()
  end

  return error(failure.message)
end

def repaired(request: Lookup.Request, keep: Int) -> Analysis.Session
  cursor = request.cursor
  text = Typing.repaired(request.documents.get(request.path).unwrap_or(""), cursor.line, cursor.chars, keep)
  return Analysis.update(request.session, request.path, text)
end
