Feature: Completion of builtins
  After a dot or at the start of a word, the editor offers the builtins of
  Agentica. The type of a variable is not known, so nothing is offered after
  the dot of a variable.

  Scenario: after a namespace and a dot the functions of that namespace are offered
    Given the language server has loaded the builtin catalog
    When the editor opens "app.agc" with:
      """
      def main() -> Void
        words = String.sp
        String.
      end

      """
    And the editor asks for completion in "app.agc" at 2:20
    And the editor asks for completion in "app.agc" at 3:10
    Then the completion at 2:20 offers:
      | label | kind     | builtin      |
      | split | Function | String.split |
    And the completion at 2:20 does not offer "upcase"
    And the completion at 3:10 offers:
      | label  | kind     | builtin       |
      | split  | Function | String.split  |
      | upcase | Function | String.upcase |
    And the completion at 3:10 does not offer "puts"

  Scenario: at the start of a word namespaces and bare functions are offered
    Given the language server has loaded the builtin catalog
    When the editor opens "app.agc" with:
      """
      def main() -> Void
        pu
        Str
      end

      """
    And the editor asks for completion in "app.agc" at 2:5
    And the editor asks for completion in "app.agc" at 3:6
    Then the completion at 2:5 offers:
      | label | kind     | builtin |
      | puts  | Function | puts    |
    And the completion at 2:5 does not offer "String"
    And the completion at 3:6 offers:
      | label  | kind   | builtin |
      | String | Module |         |
    And the completion at 3:6 does not offer "puts"

  Scenario: nothing is offered after a variable, in a comment or in a string
    Given the language server has loaded the builtin catalog
    When the editor opens "app.agc" with:
      """
      def main() -> Void
        xs = "a"
        xs.
        # String.
        t = "Str"
      end

      """
    And the editor asks for completion in "app.agc" at 3:6
    And the editor asks for completion in "app.agc" at 4:12
    And the editor asks for completion in "app.agc" at 5:11
    Then the completion at 3:6 offers nothing
    And the completion at 4:12 offers nothing
    And the completion at 5:11 offers nothing

  Scenario: a document that was never opened offers nothing
    Given the language server has loaded the builtin catalog
    When the editor asks for completion in "ghost.agc" at 1:1
    Then the completion at 1:1 offers nothing
