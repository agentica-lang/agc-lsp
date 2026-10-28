## Holds the analysis cache that the tasks share: what std/analysis kept for each open file, in an ATS table by path.
## A check publishes the entry of its file; a check or a query of that file starts from it. An entry is only a
## shortcut: std/analysis uses it while the files say what they said and checks again otherwise, so a stale or missing
## entry costs time and never a wrong answer.

import Analysis from "std/analysis"

## Is the table of the entries, by the path of the file.
export type Table = ATS[String, Analysis.Entry]

## Returns a table without entries.
export def start() -> Table
  table: Table = ATS.new()
  return table
end

## Returns the session with the cache of the entry for the path, when the table has one.
export def restored(table: Table, session: Analysis.Session, path: String) -> Analysis.Session
  case table.get(path)
    ok(entry) -> return Analysis.adopt(session, entry)
    error(_) -> return session
  end
end

## Puts the entry that the session holds for the path in the table, when it holds one.
export def publish(table: Table, session: Analysis.Session, path: String) -> Void
  case Analysis.entry(session, path)
    ok(entry) -> table.put(path, entry)
    error(_) -> return
  end
end

## Removes the entries of the files that are not in the documents, so the table holds at most one entry for each open
## document. A check that ends after its file was closed may publish once more, and the next call removes it.
export def retain(table: Table, documents: Map[String, String]) -> Void
  for path in table.keys
    if !documents.has_key?(path)
      table.delete(path)
    end
  end
end
