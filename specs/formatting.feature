Feature: Formatting
  The editor formats a document with `agentica fmt`: the server runs it on the text of the buffer, in the folder
  of the file so that the `[style]` of the manifest applies, and answers one edit that replaces the whole document.

  Scenario: an unformatted buffer is replaced by its formatted text
    Given the language server has started
    When the editor opens "app.agc" with:
      """
      def   double( n:Int)->Int
          return n*2
      end

      def main() -> Void
      puts( double(4))
      end

      """
    And the editor formats "app.agc"
    Then the formatting of "app.agc" replaces the document up to 7:0 with:
      """
      def double(n: Int) -> Int = n * 2

      def main() -> Void
        puts(double(4))
      end

      """

  Scenario: the text of the buffer is formatted, not the file on disk
    Given the language server has started
    And the file "app.agc" contains:
      """
      def main() -> Void
        puts(1)
      end

      """
    When the editor opens "app.agc" with:
      """
      def main() -> Void
      puts( 2)
      end

      """
    And the editor formats "app.agc"
    Then the formatting of "app.agc" replaces the document up to 3:0 with:
      """
      def main() -> Void
        puts(2)
      end

      """

  Scenario: a formatted buffer gets no edits
    Given the language server has started
    When the editor opens "app.agc" with:
      """
      def main() -> Void
        puts(1)
      end

      """
    And the editor formats "app.agc"
    Then the formatting of "app.agc" has no edits

  Scenario: the style of the manifest of the folder applies
    Given the language server has started
    And the file "agentica.toml" contains:
      """
      [style]
      max_line_width = 40

      """
    When the editor opens "app.agc" with:
      """
      def total(first: Int, second: Int, third: Int) -> Int
        return first + second + third
      end

      """
    And the editor formats "app.agc"
    Then the formatting of "app.agc" replaces the document up to 3:0 with:
      """
      def total(
        first: Int,
        second: Int,
        third: Int,
      ) -> Int
        first + second + third
      end

      """

  Scenario: a buffer with a syntax error gets no edits, and the reason is logged
    Given the language server has started with the arguments "--log-level debug"
    When the editor opens "app.agc" with:
      """
      def main(
      """
    And the editor formats "app.agc"
    Then the formatting of "app.agc" has no edits
    And the server logs an "info" line containing "cannot format"
    And the server logs an "info" line containing "LEX-UNCLOSED-DELIMITER"

  Scenario: columns count in the position encoding of the session
    Given the language server has started with the position encodings "utf-32"
    When the editor opens "app.agc" with:
      """
      def main() -> Void
      puts("🎉")
      end
      # 🎉
      """
    And the editor formats "app.agc"
    Then the formatting of "app.agc" replaces the document up to 3:3 with:
      """
      def main() -> Void
        puts("🎉")
      end
      # 🎉

      """

  Scenario: a document that is not open gets null
    Given the language server has started
    When the editor formats "ghost.agc"
    Then the formatting of "ghost.agc" is answered with null

  Scenario: columns count in UTF-16 code units when the editor does not offer UTF-32
    Given the language server has started
    When the editor opens "app.agc" with:
      """
      def main() -> Void
      puts("🎉")
      end
      # 🎉
      """
    And the editor formats "app.agc"
    Then the formatting of "app.agc" replaces the document up to 3:4 with:
      """
      def main() -> Void
        puts("🎉")
      end
      # 🎉

      """

  Scenario: a buffer of more than 1 MiB is formatted
    Given the language server has started
    When the editor opens "app.agc" with an unformatted buffer of 1200 KB
    And the editor formats "app.agc"
    Then the formatting of "app.agc" replaces the document with a text of 12005 lines
