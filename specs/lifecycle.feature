Feature: Server lifecycle
  The server speaks JSON-RPC over stdio with Content-Length framing. It
  announces full text sync and checks the file on disk on open and on save.

  Background:
    Given an empty folder

  Scenario: initialize announces the capabilities
    When the client runs the session:
      """
      {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}}
      {"jsonrpc":"2.0","method":"initialized","params":{}}
      {"jsonrpc":"2.0","id":2,"method":"shutdown"}
      {"jsonrpc":"2.0","method":"exit"}
      """
    Then the server answers request 1 with:
      """
      {
        "capabilities": {
          "positionEncoding": "utf-16",
          "textDocumentSync": {"openClose": true, "change": 1, "save": {"includeText": false}}
        },
        "serverInfo": {"name": "agc-lsp"}
      }
      """
    And the server answers request 2 with:
      """
      null
      """
    And the server exits with code 0

  Scenario: the client can ask for code point positions
    When the client runs the session:
      """
      {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{"general":{"positionEncodings":["utf-16","utf-32"]}}}}
      {"jsonrpc":"2.0","id":2,"method":"shutdown"}
      {"jsonrpc":"2.0","method":"exit"}
      """
    Then the server answers request 1 with:
      """
      {
        "capabilities": {
          "positionEncoding": "utf-32",
          "textDocumentSync": {"openClose": true, "change": 1, "save": {"includeText": false}}
        },
        "serverInfo": {"name": "agc-lsp"}
      }
      """

  Scenario: a request before initialize is refused
    When the client runs the session:
      """
      {"jsonrpc":"2.0","id":7,"method":"shutdown"}
      {"jsonrpc":"2.0","method":"exit"}
      """
    Then the server answers request 7 with the error code -32002
    And the server exits with code 1

  Scenario: an unknown request is not found
    When the client runs the session:
      """
      {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}}
      {"jsonrpc":"2.0","id":2,"method":"textDocument/hover","params":{}}
      {"jsonrpc":"2.0","id":3,"method":"shutdown"}
      {"jsonrpc":"2.0","method":"exit"}
      """
    Then the server answers request 2 with the error code -32601
    And the server exits with code 0

  Scenario: a message that is not JSON is a parse error
    When the client runs the session:
      """
      {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}}
      {not json
      {"jsonrpc":"2.0","id":2,"method":"shutdown"}
      {"jsonrpc":"2.0","method":"exit"}
      """
    Then the server answers with a parse error
    And the server answers request 2 with:
      """
      null
      """
    And the server exits with code 0

  Scenario: exit without shutdown ends with status 1
    When the client runs the session:
      """
      {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}}
      {"jsonrpc":"2.0","method":"exit"}
      """
    Then the server exits with code 1

  Scenario: the end of input without shutdown ends with status 1
    When the client runs the session:
      """
      {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}}
      """
    Then the server exits with code 1
