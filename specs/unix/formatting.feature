Feature: Formatting that takes long
  The agentica of these scenarios is a shell script whose `fmt` sleeps, so they run on Unix only.

  Scenario: a formatting that the editor cancels is answered as cancelled
    Given the language server has started with the arguments "--agentica specs/fixtures/slowfmt-agentica"
    When the editor opens "app.agc" with:
      """
      def main() -> Void
      puts(1)
      end

      """
    And the editor formats "app.agc" without waiting
    And the editor waits 1500 milliseconds
    And the editor cancels the formatting of "app.agc"
    Then the formatting of "app.agc" is answered as cancelled
    And the formatter of "app.agc" has stopped
