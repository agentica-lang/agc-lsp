Feature: The launcher
  Editors start the server with the `bin/agc-lsp` script, which runs it from
  wherever the script lives, also through a link to it.

  Scenario: the server starts through the launcher
    Given the language server has started through the launcher
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
