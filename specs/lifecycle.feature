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
          "textDocumentSync": {"openClose": true, "change": 0, "save": {"includeText": false}}
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

  Scenario: a notification before initialize is ignored
    Given the file "unknown.agc" contains:
      """
      def main() -> Void
        puts(oops)
      end

      """
    When the editor opens "unknown.agc" without waiting
    Then no diagnostics are published
    And the server exits with code 1

  Scenario: an unknown request is not found
    Given the language server has started
    When the editor sends the request "textDocument/hover"
    Then the server answers "textDocument/hover" with the error "method not found"
    And the server exits with code 0

  Scenario: a second initialize is refused
    Given the language server has started
    When the editor sends the request "initialize"
    Then the server answers "initialize" with the error "invalid request"
    And the server exits with code 0

  Scenario: a request after shutdown is refused
    Given the language server has started
    When the editor sends the request "shutdown"
    And the editor sends the request "textDocument/hover"
    Then the server answers "textDocument/hover" with the error "invalid request"
    And the server exits with code 0

  Scenario: a request without a method is invalid
    Given the language server has started
    When the editor sends the raw message:
      """
      {"jsonrpc":"2.0","id":99}
      """
    Then the server answers request 99 with the error "invalid request"
    And the server exits with code 0

  Scenario: a batch is invalid
    Given the language server has started
    When the editor sends the raw message:
      """
      [{"jsonrpc":"2.0","id":99,"method":"shutdown"}]
      """
    Then the server reports the error "invalid request"
    And the server exits with code 0

  Scenario: a response from the editor gets no answer
    Given the language server has started
    When the editor sends the raw message:
      """
      {"jsonrpc":"2.0","id":99,"result":null}
      """
    Then the server does not answer request 99
    And the server exits with code 0

  Scenario: a message without a Content-Length header ends the session
    Given the language server has started
    When the editor sends a message without a Content-Length header
    Then the server warns "missing or invalid Content-Length"
    And the server exits with code 1

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
