Feature: Server lifecycle
  The server speaks JSON-RPC over stdio with Content-Length framing.

  Scenario: the whole exchange, message by message
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

  Scenario: positions are UTF-16 by default
    Given the language server has started
    Then the server announces the position encoding "utf-16"

  Scenario: the editor can ask for code point positions
    Given the language server has started with the position encodings "utf-16, utf-32"
    Then the server announces the position encoding "utf-32"

  Scenario: a request before initialize is refused
    When the editor sends "shutdown" before initializing
    Then the server answers "shutdown" with the error "server not initialized"
    And the server exits with code 1

  Scenario: an unknown request is not found
    Given the language server has started
    When the editor sends the request "textDocument/hover"
    Then the server answers "textDocument/hover" with the error "method not found"
    And the server exits with code 0

  Scenario: a message that is not JSON is a parse error
    Given the language server has started
    When the editor sends a message that is not JSON
    Then the server reports the error "parse error"
    And the server exits with code 0

  Scenario: exit without shutdown ends with status 1
    Given the language server has started
    When the editor exits without shutting down
    Then the server exits with code 1

  Scenario: the end of input without shutdown ends with status 1
    Given the language server has started
    When the editor closes the connection
    Then the server exits with code 1
