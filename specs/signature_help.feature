Feature: Signature help
  Inside the parentheses of a call, the editor shows the signature of the
  function and the parameter that the cursor is on. The function can be one of
  the program, of an imported module or a builtin, and the buffer need not
  parse: the call is often unfinished while it is typed.

  Scenario: a function of the file shows its signature and the parameter that the commas count
    Given the language server has loaded the builtin catalog
    When the editor opens "app.agc" with:
      """
      def area(w: Int, h: Int) -> Int
        return w * h
      end

      def main() -> Void
        puts(area(2, 3))
      end

      """
    And the editor asks for signature help in "app.agc" at 6:13
    And the editor asks for signature help in "app.agc" at 6:16
    Then the signature help at 6:13 shows "area(w: Int, h: Int) -> Int" with the parameter "w: Int" active
    And the signature help at 6:16 shows "area(w: Int, h: Int) -> Int" with the parameter "h: Int" active

  Scenario: a function of an imported module is shown while the call is unfinished
    Given the language server has loaded the builtin catalog
    And the file "lib.agc" contains:
      """
      def area(w: Int, h: Int) -> Int = w * h
      """
    When the editor opens "app.agc" with:
      """
      import Lib from "lib"

      def main() -> Void
        puts(Lib.area(2, 
      end

      """
    And the editor asks for signature help in "app.agc" at 4:20
    Then the signature help at 4:20 shows "area(w: Int, h: Int) -> Int" with the parameter "h: Int" active

  Scenario: an argument with its name selects that parameter
    Given the language server has loaded the builtin catalog
    When the editor opens "app.agc" with:
      """
      def area(w: Int, h: Int) -> Int
        return w * h
      end

      def main() -> Void
        puts(area(h: 3, w: 2))
      end

      """
    And the editor asks for signature help in "app.agc" at 6:18
    Then the signature help at 6:18 shows "area(w: Int, h: Int) -> Int" with the parameter "h: Int" active

  Scenario: a builtin function and a builtin method show their signatures
    Given the language server has loaded the builtin catalog
    When the editor opens "app.agc" with:
      """
      def main() -> Void
        xs = [1, 2]
        puts(xs.map(
        words = String.split("a b", " ")
      end

      """
    And the editor asks for signature help in "app.agc" at 3:8
    And the editor asks for signature help in "app.agc" at 3:15
    And the editor asks for signature help in "app.agc" at 4:31
    Then the signature help at 3:8 shows "puts(value: T) -> Void" with the parameter "value: T" active
    And the signature help at 3:15 shows "list.map(block: Fn[A, B]) -> List[B]" with the parameter "block: Fn[A, B]" active
    And the signature help at 4:31 shows "String.split(string: String, separator: String) -> List[String]" with the parameter "separator: String" active

  Scenario: outside a call, in a string, in a comment and in a definition there is no signature help
    Given the language server has loaded the builtin catalog
    When the editor opens "app.agc" with:
      """
      def area(w: Int, h: Int) -> Int
        return w * h
      end

      def main() -> Void
        total = area(1, 2) + 1
        text = "area(1, 2"
        # area(1, 2
        if (total > 1)
          puts(total)
        end
      end

      """
    And the editor asks for signature help in "app.agc" at 6:22
    And the editor asks for signature help in "app.agc" at 7:19
    And the editor asks for signature help in "app.agc" at 8:15
    And the editor asks for signature help in "app.agc" at 9:8
    And the editor asks for signature help in "app.agc" at 1:12
    Then there is no signature help at 6:22
    And there is no signature help at 7:19
    And there is no signature help at 8:15
    And there is no signature help at 9:8
    And there is no signature help at 1:12
