Feature: Diagnostics of the file on disk
  On open and on save the server runs `agentica --json check` on the file and
  publishes its first diagnostic, or an empty list when it checks. Lines and
  characters count from 0; the end of a range is exclusive.

  Background:
    Given an empty folder
    And the file "good.agc":
      """
      def main() -> Void
        puts("hi")
      end

      """
    And the file "unknown.agc":
      """
      def main() -> Void
        puts(oops)
      end

      """

  Scenario: a file that checks publishes no diagnostics
    When the client runs the session:
      """
      {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}}
      {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"${URI}/good.agc","languageId":"agentica","version":1,"text":""}}}
      {"jsonrpc":"2.0","id":2,"method":"shutdown"}
      {"jsonrpc":"2.0","method":"exit"}
      """
    Then the diagnostics published for "good.agc" are, in order:
      """
      [[]]
      """

  Scenario: a file with an error publishes its first diagnostic
    When the client runs the session:
      """
      {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}}
      {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"${URI}/unknown.agc","languageId":"agentica","version":1,"text":""}}}
      {"jsonrpc":"2.0","id":2,"method":"shutdown"}
      {"jsonrpc":"2.0","method":"exit"}
      """
    Then the diagnostics published for "unknown.agc" are, in order:
      """
      [[{
        "range": {"start": {"line": 1, "character": 7}, "end": {"line": 1, "character": 11}},
        "severity": 1,
        "code": "CHECK-UNKNOWN-NAME",
        "source": "agentica",
        "message": "unknown name \"oops\""
      }]]
      """

  Scenario: the help of a diagnostic follows its message
    Given the file "types.agc":
      """
      def main() -> Void
        age: Int = "25"
      end

      """
    When the client runs the session:
      """
      {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}}
      {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"${URI}/types.agc","languageId":"agentica","version":1,"text":""}}}
      {"jsonrpc":"2.0","id":2,"method":"shutdown"}
      {"jsonrpc":"2.0","method":"exit"}
      """
    Then the diagnostics published for "types.agc" are, in order:
      """
      [[{
        "range": {"start": {"line": 1, "character": 13}, "end": {"line": 1, "character": 17}},
        "severity": 1,
        "code": "CHECK-TYPE-MISMATCH",
        "source": "agentica",
        "message": "expected Int, found String\nhelp: convert it with String.to_int!(...)"
      }]]
      """

  Scenario Outline: characters count in the negotiated encoding
    Given the file "emoji.agc":
      """
      def main() -> Void
        names = ["😀", oops]
      end

      """
    When the client runs the session:
      """
      {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{"general":{"positionEncodings":<offered>}}}}
      {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"${URI}/emoji.agc","languageId":"agentica","version":1,"text":""}}}
      {"jsonrpc":"2.0","id":2,"method":"shutdown"}
      {"jsonrpc":"2.0","method":"exit"}
      """
    Then the diagnostics published for "emoji.agc" are, in order:
      """
      [[{
        "range": {"start": {"line": 1, "character": <start>}, "end": {"line": 1, "character": <end>}},
        "severity": 1,
        "code": "CHECK-UNKNOWN-NAME",
        "source": "agentica",
        "message": "unknown name \"oops\""
      }]]
      """

    Examples:
      | offered             | start | end |
      | ["utf-16"]          | 17    | 21  |
      | ["utf-16","utf-32"] | 16    | 20  |

  Scenario: saving a fixed file clears its diagnostic
    When the client runs the session:
      """
      {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}}
      {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"${URI}/unknown.agc","languageId":"agentica","version":1,"text":""}}}
      > await diagnostics
      > copy good.agc to unknown.agc
      {"jsonrpc":"2.0","method":"textDocument/didChange","params":{"textDocument":{"uri":"${URI}/unknown.agc","version":2},"contentChanges":[{"text":""}]}}
      {"jsonrpc":"2.0","method":"textDocument/didSave","params":{"textDocument":{"uri":"${URI}/unknown.agc"}}}
      {"jsonrpc":"2.0","id":2,"method":"shutdown"}
      {"jsonrpc":"2.0","method":"exit"}
      """
    Then the diagnostics published for "unknown.agc" are, in order:
      """
      [
        [{
          "range": {"start": {"line": 1, "character": 7}, "end": {"line": 1, "character": 11}},
          "severity": 1,
          "code": "CHECK-UNKNOWN-NAME",
          "source": "agentica",
          "message": "unknown name \"oops\""
        }],
        []
      ]
      """

  Scenario: closing a file clears its diagnostic
    When the client runs the session:
      """
      {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}}
      {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"${URI}/unknown.agc","languageId":"agentica","version":1,"text":""}}}
      {"jsonrpc":"2.0","method":"textDocument/didClose","params":{"textDocument":{"uri":"${URI}/unknown.agc"}}}
      {"jsonrpc":"2.0","id":2,"method":"shutdown"}
      {"jsonrpc":"2.0","method":"exit"}
      """
    Then the diagnostics published for "unknown.agc" are, in order:
      """
      [
        [{
          "range": {"start": {"line": 1, "character": 7}, "end": {"line": 1, "character": 11}},
          "severity": 1,
          "code": "CHECK-UNKNOWN-NAME",
          "source": "agentica",
          "message": "unknown name \"oops\""
        }],
        []
      ]
      """

  Scenario: an error in an imported file is shown at the start of the opened file
    Given the file "lib.agc":
      """
      export def answer() -> Int
        return "a"
      end

      """
    And the file "app.agc":
      """
      import Lib from "lib"

      def main() -> Void
        puts(Lib.answer())
      end

      """
    When the client runs the session:
      """
      {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}}
      {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"${URI}/app.agc","languageId":"agentica","version":1,"text":""}}}
      {"jsonrpc":"2.0","id":2,"method":"shutdown"}
      {"jsonrpc":"2.0","method":"exit"}
      """
    Then the diagnostics published for "app.agc" are, in order:
      """
      [[{
        "range": {"start": {"line": 0, "character": 0}, "end": {"line": 0, "character": 0}},
        "severity": 1,
        "code": "CHECK-TYPE-MISMATCH",
        "source": "agentica",
        "message": "${DIR}/lib.agc:2:10: expected Int, found String\nhelp: convert it with String.to_int!(...)"
      }]]
      """

  Scenario: a file that is gone publishes no diagnostics
    When the client runs the session:
      """
      {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}}
      {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"${URI}/missing.agc","languageId":"agentica","version":1,"text":""}}}
      {"jsonrpc":"2.0","id":2,"method":"shutdown"}
      {"jsonrpc":"2.0","method":"exit"}
      """
    Then the diagnostics published for "missing.agc" are, in order:
      """
      [[]]
      """
    And the server exits with code 0
