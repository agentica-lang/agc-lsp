## Tells which errors of a question to std/analysis are no failure of the server: the program has a problem, or the
## position names nothing.

import Analysis from "std/analysis"
import Logger from "std/logger"

POSITION_CODES = ["LEX-", "PARSE-", "CHECK-", "QUERY-NO-EXPRESSION"]
SEARCH_CODES = ["LEX-", "PARSE-", "QUERY-NOT-FOUND"]

## Returns true when the error of a question about a position says only that the program or the position is what it
## is, and logs it at debug level.
export def at_position?(message: String) -> Bool
  return refused?(message, POSITION_CODES)
end

## Returns true when the error of a search by name says only that the name or a file is what it is, and logs it at
## debug level.
export def in_search?(message: String) -> Bool
  return refused?(message, SEARCH_CODES)
end

def refused?(message: String, prefixes: List[String]) -> Bool
  case Analysis.diagnostic(message)
    ok(found) ->
      if prefixes.any? do |prefix| found.code.starts_with?(prefix) end
        Logger.debug("the query was refused: #{found.code}")
        return true
      end

      return false
    error(_) -> return false
  end
end
