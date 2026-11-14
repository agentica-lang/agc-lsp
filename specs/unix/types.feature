Feature: Builtin types
  Since Agentica 0.32.0, `agentica --json help` lists the builtin types next to
  the functions: a row with a `kind` (struct, enum or opaque) is a type. The
  editor offers a type as a type and its hover shows the declaration. The
  agentica of these scenarios adds the rows of `specs/fixtures/types.json` to
  the catalog of the agentica in PATH, so they run on older releases too.

  Scenario: a type of a namespace is offered as a type after the dot, and a bare type at the start of a word
    Given the language server has loaded the builtin catalog of "specs/fixtures/types-agentica"
    When the editor opens "app.agc" with:
      """
      def main() -> Void
        a = File.In
        b = System.Sig
        c = Er
        d = Proc
      end

      """
    And the editor asks for completion in "app.agc" at 2:14
    And the editor asks for completion in "app.agc" at 3:17
    And the editor asks for completion in "app.agc" at 4:9
    And the editor asks for completion in "app.agc" at 5:11
    Then the completion at 2:14 offers:
      | label | kind   | builtin   |
      | Info  | Struct | File.Info |
    And the completion at 3:17 offers:
      | label  | kind | builtin       |
      | Signal | Enum | System.Signal |
    And the completion at 4:9 offers:
      | label | kind   | builtin |
      | Error | Struct | Error   |
    And the completion at 5:11 offers:
      | label   | kind   | builtin |
      | Process | Class  | Process |
    And the completion at 5:11 offers "Process" once

  Scenario: a type shows its declaration with its fields or variants
    Given the language server has loaded the builtin catalog of "specs/fixtures/types-agentica"
    When the editor opens "app.agc" with:
      """
      def first(info: File.Info, ready: Await[Int], p: Process) -> Error
        return Error(message: "x")
      end

      """
    And the editor hovers over "app.agc" at 1:24
    And the editor hovers over "app.agc" at 1:36
    And the editor hovers over "app.agc" at 1:50
    And the editor hovers over "app.agc" at 2:12
    Then the hover at 1:24 reads:
      """
      ```agc
      struct File.Info
        kind: String
        size_bytes: Int
        modified_seconds: Int
        mode: Int
        user_id: Int
        group_id: Int
      end
      ```

      What File.stat returns: the kind, byte size, modification time, permission bits and owner of a file.
      """
    And the hover at 1:24 covers 1:17-1:26
    And the hover at 1:36 reads:
      """
      ```agc
      enum Await[T]
        Done(T)
        TimedOut
      end
      ```

      What Task.await with a timeout returns: Done with the task's value, or TimedOut.
      """
    And the hover at 1:50 reads:
      """
      ```agc
      type Process
      ```

      A program started by Process.spawn, Process.spawn_captured or Process.spawn_channel.
      """
    And the hover at 2:12 reads:
      """
      ```agc
      struct Error
        kind: String = "error"
        message: String
        code: Optional[Int] = none
        details: Map[String, String] = {}
        cause: Optional[Error] = none
        location: String = ""
      end
      ```

      The payload of a failed Result: its kind, message, code, details, cause and the place it was made.
      """
