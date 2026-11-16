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
    And the editor formats "app.agc" and cancels the request
    Then the formatting of "app.agc" is answered as cancelled
