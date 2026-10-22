Feature: The launcher
  Editors start the server with the `bin/agc-lsp` script, which runs it from
  wherever the script lives, also through a link to it. The server imports
  `std/analysis`, which takes seconds to compile, so the launcher compiles it
  once and keeps the program in a cache, named by the version of agentica and
  the text of the sources.

  Scenario: the server starts through a link to the launcher
    Given the language server has started through a link to the launcher
    And the file "unknown.agc" contains:
      """
      def main() -> Void
        puts(oops)
      end

      """
    When the editor opens "unknown.agc"
    Then "unknown.agc" gets these diagnostics:
      | at       | severity | code               |
      | 2:8-2:12 | error    | CHECK-UNKNOWN-NAME |

  Scenario: the server starts through a relative link to the launcher
    Given the language server has started through a relative link to the launcher
    And the file "unknown.agc" contains:
      """
      def main() -> Void
        puts(oops)
      end

      """
    When the editor opens "unknown.agc"
    Then "unknown.agc" gets these diagnostics:
      | at       | severity | code               |
      | 2:8-2:12 | error    | CHECK-UNKNOWN-NAME |

  Scenario: the server is compiled once and the next start uses the cache
    Given a copy of the launcher with the server source:
      """
      def main() -> Void
        puts("serving")
      end
      """
    When the launcher runs
    And the launcher runs
    Then the launcher exits with code 0
    And the launcher printed "serving"
    And the cache holds 1 compiled server

  Scenario: a change in the source of the server is compiled into another program
    Given a copy of the launcher with the server source:
      """
      def main() -> Void
        puts("serving")
      end
      """
    When the launcher runs
    And the server source changes to:
      """
      def main() -> Void
        puts("serving again")
      end
      """
    And the launcher runs
    Then the launcher printed "serving again"
    And the cache holds 2 compiled servers

  Scenario: a server that does not compile reports the error and caches nothing
    Given a copy of the launcher with the server source:
      """
      def main() -> Void
        puts(oops)
      end
      """
    When the launcher runs
    Then the launcher exits with code 1
    And the launcher reported "CHECK-UNKNOWN-NAME"
    And the cache holds 0 compiled servers
