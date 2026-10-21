Feature: Logging
  The server logs to three places, each with its own level: stderr (what editors
  show in their LSP log; default warning), the editor as log messages (default
  error) and an optional JSON lines file (the level of stderr).

  Scenario: a failed check warns on stderr and stays out of the editor by default
    Given the language server has started with the arguments "--agentica specs/fixtures/silent-agentica"
    And the file "unknown.agc" contains:
      """
      def main() -> Void
        puts(oops)
      end

      """
    When the editor opens "unknown.agc" without waiting
    And the editor waits 1500 milliseconds
    Then the server logs a "warning" line containing "no diagnostic"
    And the editor gets no log messages
    And the server logs no "info" lines
    And the server logs no "debug" lines

  Scenario: the editor can ask for the warnings of the server
    Given the language server has started with the arguments "--client-log-level warning --agentica specs/fixtures/silent-agentica"
    And the file "unknown.agc" contains:
      """
      def main() -> Void
        puts(oops)
      end

      """
    When the editor opens "unknown.agc" without waiting
    And the editor waits 1500 milliseconds
    Then the editor gets a "warning" log message containing "no diagnostic"
    And the server logs a "warning" line containing "no diagnostic"

  Scenario: the start and the end of a check are logged at debug level
    Given the server writes its log to "server.log"
    And the language server has started with the arguments "--log-level debug --client-log-level debug"
    And the file "ok.agc" contains:
      """
      def main() -> Void
        puts("hidden-text")
      end

      """
    When the editor opens "ok.agc"
    Then "ok.agc" gets no diagnostics
    And the server logs a "debug" line containing "check started"
    And the server logs a "debug" line containing "check finished"
    And the server logs a "debug" line containing "textDocument/didOpen"
    And the server never logs "hidden-text"
    And the editor gets no log message containing "hidden-text"
    And the log file "server.log" never contains "hidden-text"

  Scenario: the starting, the initialization and the shutdown are logged at info level
    Given the language server has started with the arguments "--log-level info --agentica specs/fixtures/noisy-agentica"
    Then the server logs an "info" line containing "starting"
    And the server logs an "info" line containing "specs/fixtures/noisy-agentica"
    And the server logs an "info" line containing "initialized"
    And the server logs an "info" line containing "shutting down"
    And the server logs no "debug" lines

  Scenario: the editor can set the level of stderr
    Given the editor asks for the log level "debug"
    And the language server has started
    And the file "ok.agc" contains:
      """
      def main() -> Void
        puts("hi")
      end

      """
    When the editor opens "ok.agc"
    Then "ok.agc" gets no diagnostics
    And the server logs a "debug" line containing "check started"

  Scenario: the editor can set the level of its own log messages
    Given the editor asks for the client log level "info"
    And the language server has started
    Then the editor gets an "info" log message containing "initialized"

  Scenario: a level on the command line wins over the one of the editor
    Given the editor asks for the log level "debug"
    And the editor asks for the client log level "debug"
    And the language server has started with the arguments "--log-level error --client-log-level error --agentica specs/fixtures/silent-agentica"
    And the file "unknown.agc" contains:
      """
      def main() -> Void
        puts(oops)
      end

      """
    When the editor opens "unknown.agc" without waiting
    And the editor waits 1500 milliseconds
    Then the server logs no "debug" lines
    And the server logs no "warning" lines
    And the editor gets no log messages

  Scenario: a level on the command line wins over a quieter one of the editor
    Given the editor asks for the log level "error"
    And the language server has started with the arguments "--log-level debug"
    And the file "ok.agc" contains:
      """
      def main() -> Void
        puts("hi")
      end

      """
    When the editor opens "ok.agc"
    Then "ok.agc" gets no diagnostics
    And the server logs a "debug" line containing "check started"

  Scenario: the editor gets the levels of the server as log message types
    Given the language server has started with the arguments "--client-log-level debug"
    And the file "ok.agc" contains:
      """
      def main() -> Void
        puts("hi")
      end

      """
    When the editor opens "ok.agc"
    Then "ok.agc" gets no diagnostics
    And the editor gets a "debug" log message containing "check finished"
    And the editor gets an "info" log message containing "initialized"

  Scenario: a lost framing is an error for the editor too
    Given the language server has started
    When the editor sends a message without a Content-Length header
    Then the server logs an "error" line containing "Content-Length"
    And the editor gets an "error" log message containing "Content-Length"

  Scenario: a log file gets JSON lines
    Given the server writes its log to "server.log"
    And the language server has started with the arguments "--log-level info --agentica specs/fixtures/silent-agentica"
    And the file "unknown.agc" contains:
      """
      def main() -> Void
        puts(oops)
      end

      """
    When the editor opens "unknown.agc" without waiting
    And the editor waits 1500 milliseconds
    Then the log file "server.log" has a "warning" line containing "no diagnostic"
    And the log file "server.log" has an "info" line containing "starting"
    And the log file "server.log" has only JSON lines

  Scenario: the log file does not get what is below the level
    Given the server writes its log to "server.log"
    And the language server has started with the arguments "--agentica specs/fixtures/silent-agentica"
    And the file "unknown.agc" contains:
      """
      def main() -> Void
        puts(oops)
      end

      """
    When the editor opens "unknown.agc" without waiting
    And the editor waits 1500 milliseconds
    Then the log file "server.log" has a "warning" line containing "no diagnostic"
    And the log file "server.log" has no "info" lines

  Scenario: stderr can be written as JSON lines
    Given the language server has started with the arguments "--log-format json --log-level info"
    Then the server logs only JSON lines
    And the server logs an "info" line containing "shutting down"

  Scenario: a log file that cannot be written is warned about
    Given the language server has started with the arguments "--log-file /agc-lsp-missing/server.log"
    Then the server warns "cannot write the log file"

  Scenario Outline: an unknown level or format is warned about and the default is kept
    Given the language server has started with the arguments "<option> <value>"
    Then the server warns "unknown <what> <value>"
    And the server logs no "info" lines
    And the server exits with code 0

    Examples:
      | option             | value | what       |
      | --log-level        | loud  | log level  |
      | --client-log-level | loud  | log level  |
      | --log-format       | xml   | log format |

  Scenario: an option without a value is warned about
    Given the language server has started with the arguments "--log-level"
    Then the server warns "needs a value"

  Scenario Outline: an unknown level from the editor is warned about and the default is kept
    Given the editor asks for the log level "<level>"
    And the language server has started
    Then the server warns "unknown log level <level>"
    And the server logs no "info" lines

    Examples:
      | level |
      | loud  |
      | null  |

  Scenario: the editor gets nothing before the answer to initialize
    Given the editor asks for the log level "loud"
    And the editor asks for the client log level "warning"
    And the language server has started
    Then the editor gets a "warning" log message containing "unknown log level loud"
    And the answer to initialize comes before the log messages

  Scenario: logging to the editor and to stderr does not slow down many checks
    Given the language server has started with the arguments "--log-level debug --client-log-level debug --agentica specs/fixtures/crowded-agentica"
    And the files "one.agc, two.agc, three.agc, four.agc, five.agc, six.agc" contain:
      """
      def main() -> Void
        puts(oops)
      end

      """
    When the editor opens the files "one.agc, two.agc, three.agc, four.agc, five.agc, six.agc" without waiting
    And the editor waits for the diagnostics of 6 files
    Then "six.agc" gets these diagnostics:
      | at       | severity | code               |
      | 2:8-2:12 | error    | CHECK-UNKNOWN-NAME |
    And the server exits with code 0
