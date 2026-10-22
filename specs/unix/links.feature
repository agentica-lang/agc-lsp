Feature: Files reached through links
  A folder can be reached through a link, and a URI can name a file with a double slash.
  Making a link needs `ln`, so these scenarios run on Linux and macOS only.

  Scenario: a file reached through a link and a double slash keeps its position
    Given the language server has started
    And the folder has the link "link" to itself
    And the file "unknown.agc" contains:
      """
      def main() -> Void
        puts(oops)
      end

      """
    When the editor opens "link//unknown.agc"
    Then "link//unknown.agc" gets these diagnostics:
      | at       | severity | code               |
      | 2:8-2:12 | error    | CHECK-UNKNOWN-NAME |
