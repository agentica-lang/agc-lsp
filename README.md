# agc-lsp

A Language Server Protocol (LSP) server for [Agentica](https://github.com/sonic182/agentica), a language for AI agents,
written in Agentica.

> **Status:** early stage. Diagnostics of the text in the editor's buffers, hover, completion, go to definition, find
> references, document symbols and workspace symbols, all answered in-process with `std/analysis`.

## What it does

- Speaks JSON-RPC over stdio with `Content-Length` framing: `initialize`, `shutdown`, `exit`.
- Answers everything in-process with `std/analysis`: the server keeps one analysis session that holds the text of every
  open document, so an unsaved change is seen by the checks and the queries of every open file, imported files
  included. It starts no `agentica` process, apart from the one that prints the catalog of builtins.
- It asks for full document sync. On `textDocument/didOpen`, `textDocument/didChange` and `textDocument/didSave` it
  checks the text of the buffer (a file that is not saved, or not on disk, is checked as the editor shows it; its
  imports and `agentica.toml` resolve from its folder) and publishes its first diagnostic, or an empty list.
  `textDocument/didClose` clears it.
- An error in an imported file, or in the `agentica.toml` that the check finds above the file, is shown at the start of
  the opened file, with the imported file and position in the message and in `relatedInformation`, whose location
  points into that file (the start of the file for an error at a key of `agentica.toml`). The imported file is read
  from its open buffer when the editor has it open.
- Typing in a file, or saving it, checks again the other open files whose current diagnostic points into it, so fixing
  an imported file clears the error shown on the files that import it, saved or not.
- Hover and completion of the Agentica builtins come from the catalog that `agentica --json help` prints, loaded once
  per session in a task (a completion is an empty list until it arrives).
  - Hover (markdown): on `String.split` (on either part of the name) the signature in an `agc` code block and the
    description; on a bare builtin call such as `puts(`. The range is the whole qualified name. Nothing in a string or
    in a `#` comment. These two answer at once, without asking the session.
  - Hover on anything else asks the session for the type at the position, in the text of the buffer
    (`Analysis.type_at_partial`):
    - A method call such as `xs.split(",")` shows the one builtin that it is (the signature and the description, as for
      `String.split`), because the type of the receiver is known; the range is the method name. If the function has an
      error, so that there is no type, every builtin of that name is shown instead (`List.size`, `Map.size`, ...).
    - A function, struct, enum, variant, field or constant shows its signature in an `agc` code block, then its `##`
      doc (CommonMark, as written), then a rule (`---`) and the type of the expression under the cursor, such as
      `Lib.greet("Ana"): String`, with its range.
    - A type name (in a parameter, a return type, a field or a type argument, also through an import such as
      `Models.User`) shows the declaration of the struct, enum or alias and its doc.
    - A local, a parameter, a loop name or a pattern name shows the type only, such as `text: String`.
    - A name that resolves inside a function with an error shows its declaration without a type; where the position
      itself has an error there is no hover.
  - Completion (trigger character `.`): after `String.` and a partial name, the functions of that namespace; at the
    start of a word, the namespaces and the bare functions that start with it (at a blank position, every namespace and
    bare function); nothing after `x.` when `x` is not a namespace, in a string or in a comment. Each item has a
    `textEdit` that replaces the partial word before the cursor, so names ending in `?` or `!` complete correctly. A
    position past the end of a line means the end of the line.
- Go to definition (`textDocument/definition`) asks the session about the position (`Analysis.type_at_partial`), in
  the text of the buffer, and answers the location of the name of the declaration: a function, struct, enum, variant,
  field, constant, type name, local, parameter, loop name or pattern name, in the same file or in an imported file (a
  `std/` module is not on disk, so it has no location). A builtin, a comment, a name that is not declared and a
  position inside a function with an error that gives no type have none (`null`). The other functions of the file may
  have errors.
- Document symbols (`textDocument/documentSymbol`) are the outline of the buffer (`Analysis.outline`), as a hierarchy:
  constants, functions, structs with their fields, enums with their variants and type aliases. The range is the
  declaration, the selection range its name and the detail its signature. The outline only parses, so a file with a
  type error is listed too; a file with a syntax error gets `null`.
- Find references (`textDocument/references`) asks the session about the position (`Analysis.refs_partial`), in the
  text of the buffer, and answers the locations of the uses of the name: a function, struct, enum, variant, field,
  constant, local, parameter, loop name, pattern name or builtin, in the same file and in the files that it imports
  (and they import). The declaration is the first location unless the client sets `context.includeDeclaration` to
  `false`; a builtin has none. A name used in a function with an error is found in the other functions, as for
  definition. A comment, a string, a keyword, a blank or a document that is not open answers `null` without asking, and
  so does a position where the analysis finds no expression. A `std/` module is not on disk, so its declaration is not
  listed.
- Workspace symbols (`workspace/symbol`) ask the session where a name is declared (`Analysis.symbol`) in the workspace
  folder and in the open documents, and answer symbol information with the kind of the declaration (as in document
  symbols; a field or a variant has its struct or enum as `containerName`) and the range of its name. The query must be
  the whole name as the code declares it, with the same case: `area`, `Point`, `Point.x` (a field), `Shape.Circle` (a
  variant), `Models.greet` (through the alias of an import in some file of the workspace). The analysis does not match
  prefixes or fuzzily, so `are` finds nothing. A name that is not declared answers an empty list. An empty query, a
  query that starts with `-` (a name never does) and an editor that gave no workspace folder answer an empty list
  without asking. The folder is the first of `workspaceFolders` of `initialize`, else `rootUri`, else `rootPath`; a
  client with several folders is searched in the first only.
- Positions are UTF-16 by default, or code points when the client offers `utf-32`.

## Limitations

- Only `.agc` files are checked.
- Checks run one at a time, in the order in which they are due, because two refreshes of one session give two caches
  and keeping one drops the work of the other. A check refreshes the session for its file (`Analysis.refresh`, which
  links and checks the program once and keeps it in the cache of the session) and then checks it. The refreshed session
  is stored only when no document changed while the check ran; otherwise it is dropped. A newer `didOpen`, `didChange`,
  `didSave` or `didClose` of the same file cancels its older check, whose result is never published, so quick changes
  publish only the diagnostics of the last text. A change in any open file cancels the running check of another file
  and puts it back in the queue, behind the check of the file that changed. A check requested by `didChange` waits 200
  ms for the next change before it starts (a newer change replaces its text and restarts the wait), and so does the re-
  check of the files that point into the changed file; `didOpen` and `didSave` start at once. A `didSave` of a document
  that is not open checks nothing itself (it still re-checks the open files that point into it).
- Questions (hover, definition, references, symbols) run on the session as it was when they arrived, which can be one
  that no check has refreshed yet while the user types, so they can answer from an older program until the next check
  ends. Typing never waits for longer than the check that runs.
- Two URIs for one path (for example a `localhost` authority or a double slash) share one open text and one entry of
  the session: the last text written under either is the one every check sees. Each URI is still checked and published
  on its own, and the text stays until the last of them is closed.
- A crash of a check task is logged as an error and leaves the previous diagnostics; a crash of the catalog task is
  logged as an error and leaves hover and completion empty.
- Completion knows the builtins only, not your own functions, structs or imports (nor the `std/` modules), and
  `xs.` completes nothing. Strings and comments are found with a scan of the line, so a heredoc, a string that spans
  lines or code inside `#{}` is not recognised. A catalog that cannot be loaded (see Logging) leaves completion empty
  for the session, and the hover of a qualified builtin or a bare call then comes from the type at the position, so it
  needs a function that checks.
- Definition, references, hover and document symbols run in tasks on the session as it was when the request came, so
  the server loop never waits for them, and the answer is for the text that the buffer had then, even if it changed or
  was closed meanwhile. At most 4 of these tasks run at once; the other requests wait in the order they came. A newer
  hover, definition, references or symbols request for the same document supersedes the older ones of the same kind,
  and a newer workspace symbol request supersedes the older ones (of the same workspace folder); they are answered with
  `null` and their task is cancelled. A hover, definition or references request on a comment, a string, a keyword or a
  blank answers `null` without asking. A `$/cancelRequest` answers the request with the error `-32800` (request
  cancelled). At `shutdown` the requests still in flight are answered with `null` before the answer to `shutdown`. A
  query that fails answers `null` and logs a warning; a position or a program that the analysis refuses (an error in
  the program, no expression there) answers `null` and logs at debug level only.
- A `std/` module is not a file on disk, so a name declared there has no location, though its hover has the signature
  and the doc. A function with an error gives no type, so definition and hover work in the other functions and on the
  names that resolve in that one, but not on an expression that has the error. The name of a variant in a `case`
  pattern (`Shape.Circle(r)`) gives nothing yet, in any of these requests.
- A query reads the files again and uses the cache of the session only where the modules and their texts are those
  it was made from, so an answer takes from some milliseconds when the file was checked since its last change, and as
  long as a check of the file when it was not (the first request after a change, until the check of the change has
  run). A file that imports `std/analysis` (this server does) links the whole compiler, so a check of it takes about a
  second.
- References are those in the buffer and the files it links: a file that only imports the name, and that the buffer
  does not import, is not searched. Asked on a declaration in a module, it lists the uses in that module and in what
  it imports, not in the files that import it; asked on a use in a file that imports the module, it lists the uses in
  that file and in the module. The imported files are read from their open buffers, else from disk. References need
  the program to check apart from the functions with an error: a field, a local or a keyword inside a function with an
  error gives `null`.
- Workspace symbols read every `.agc` file below the workspace folder from disk (not the hidden folders, `agc_libs/`
  or links) and every open document, as the editor shows it, wherever it is; a saved file whose buffer changed has the
  positions of the buffer. A file that does not parse is left out, and logged at debug level; the others still answer.
  Declarations of `std/` modules and builtins are not listed (they have no place).
- The files of the disk are read relative to the working folder of the server, and the analysis names the files below
  it relative to that folder; the server makes them absolute, so any folder works.
- The VS Code extension has not been tested in VS Code.
- Windows: CI starts the server through `bin\agc-lsp.bat` (smoke test only) and runs the other specs that need no `ln`
  or `c:` folders through the shell launcher, with the `windows-x86_64` release of agentica. A file URI with a drive
  letter (`file:///c%3A/dir/a.agc` or `file:///C:/dir/a.agc`) is read as the path `c:/dir/a.agc` (lower case drive
  letter, `/` for `\`), and the locations that the server writes use that form. Neither editor extension has been tried
  on Windows, and the features in `specs/unix/` (the launcher and links) are not run there. A UNC path or a `\\?\` path
  is not handled. The VS Code client starts `agc-lsp.bat` through `cmd.exe`, so killing the editor hard can leave the
  server running as an orphan. When the server compares paths (for example to find the unsaved text of a file), only
  the drive letter is folded to lower case; the rest of the path must match in case, as the server sees it.
- An error in an imported file is published on the file that was opened, never on the imported file itself. Typing in
  or saving a file checks again only the open files whose current diagnostic points into it. A file that imports it
  and showed no error is not checked again until it is changed, saved or reopened, so a new error that you type in an
  imported file appears on the files that import it when they are checked next.
- A diagnostic in a library module or package file (not an absolute path) has the prefix in its message but no related
  location.

## Usage

It needs `agentica` 0.8.1 or later on `PATH`, and `bash` on Linux and macOS or `cmd.exe` on Windows (the server imports
`std/analysis`, and its type names, `type_at_partial` and `refs_partial` come with 0.8.1). The programs that import
`std/analysis` take about 3 s to start from source, because they compile the compiler, so the launcher compiles the
server once and keeps the program:

```sh
bin/agc-lsp [--stdio] [--agentica PATH] [--log-level LEVEL] [--client-log-level LEVEL] \
  [--log-format text|json] [--log-file PATH]
```

On Windows the launcher is `bin\agc-lsp.bat`, with the same options.

Both launchers are thin: they find the folder of the repository, ask `bin/prepare.agc` (an Agentica program that does
not import `std/analysis`, so it starts in a few tens of milliseconds) for the path of the compiled server, and run it
with `agentica run --allow-run`. `bin/prepare.agc` keeps the compiled program in the `agc-lsp` folder of the user cache
of the system:

| System | Cache folder |
| --- | --- |
| Linux, macOS | `$XDG_CACHE_HOME/agc-lsp`, else `$HOME/.cache/agc-lsp` |
| Windows | `%LOCALAPPDATA%\agc-lsp` |

`AGC_LSP_CACHE` names the cache folder itself, on every system, and wins over the table (the specs and `make smoke` set
it so that they never write to your cache).

The program is `KEY.agcb`, where KEY is a SHA-256 of the resolved path of the `agentica` binary, the output of
`agentica --version` and the names and text of `src/*.agc`, so another `agentica` or a change of the sources compiles
again (about 3 s, with the error of agentica on stderr and a non-zero status if it does not compile) and anything else
starts in about 0.03 s. The program is compiled into a temporary file of the same folder and moved into place with
`Path.rename`, which is atomic and never replaces an existing file: a program that exists is complete, two editors that
start at once may both compile, one move wins and the other start uses the winner and removes its temporary file, and
no lock is needed. A file system that cannot do that kind of rename (some network homes answer `EINVAL`) makes the
launcher exit with status 1 and an error that names the cache folder: set `AGC_LSP_CACHE` (or `XDG_CACHE_HOME`) to a
folder on a local disk. The cache folder is made private to you (`Dir.mkdir_private`). Each start writes the time to
`KEY.agcb.used`, because agentica has no way to set the modification time of a file; when a new program is compiled,
the programs whose stamp (or file, without a stamp) is older than 30 days are removed, except the one that is about to
run, and so are temporary files older than an hour (also the `compiling.*` files of the first version of the launcher).
The server runs with `agentica run --allow-run`, which it needs to print the catalog.

`--agentica PATH` names the binary that prints the builtin catalog (default: `agentica` from `PATH`); the checks and
the queries are the ones of the binary that compiled the server. `--stdio` is accepted for clients that pass it; stdio
is the only transport. The logging options are described below.

## Editors

`bin/agc-lsp` (`bin\agc-lsp.bat` on Windows) starts the server from wherever the script lives (on Linux and macOS a
symlink to it works too) and passes its arguments on. It uses the `agentica` on `PATH`, or the binary named by the
`AGENTICA` environment variable, to compile and to run the server. To have `agc-lsp` on `PATH`:

```sh
ln -s "$PWD/bin/agc-lsp" ~/.local/bin/agc-lsp
```

On Windows, add the `bin` folder of the repository to `PATH` (then `agc-lsp` finds `agc-lsp.bat`), or give the full
path of `bin\agc-lsp.bat` to the editor. Install `agentica` from the `windows-x86_64` archive of its release and put
its `bin` folder on `PATH` too. `AGENTICA` on Windows must name the `agentica.exe` itself, not a `.cmd` shim, because
the launcher hands it to `agentica` programs that start it as a process, which only runs `.exe` files.

- Neovim 0.11+: [editors/nvim/agentica.lua](editors/nvim/agentica.lua) (a note for 0.10 and for Windows is in the
  file).
- VS Code: [editors/vscode](editors/vscode), a minimal extension to install from a `.vsix` (see its README).

Syntax highlighting is not part of this repository; it will come from
[agentica-lang/agc-tmlanguage](https://github.com/agentica-lang/agc-tmlanguage).

## Timings

Median milliseconds for a request or an edit, on a machine with 12 threads (the numbers move by tens of milliseconds
from run to run). The files are `src/main.agc` and `src/server.agc`; the first table is of the sources before this
server imported `std/analysis` (about 3,000 lines that import each other), with `agentica` started for every check and
query (the old way) and with the session (the new way). "Typing" is the time from a `didChange` to the diagnostics, and
includes the 200 ms that a change waits.

| | `agentica` processes | session |
| --- | --- | --- |
| check on open | 122 | 100 to 205 |
| typing | 320 | 350 to 470 |
| hover | 117 to 120 | 20 to 23 (83 to 180 before the first check ends) |
| definition | 118 to 121 | 16 to 22 |
| references | 128 to 131 | 29 to 31 |
| document symbols | 10 to 25 | 1 to 16 |
| workspace symbols | 155 | 110 |

The sources of this server import `std/analysis`, so checking them links the whole compiler: `agentica check
--stdin` takes 1,250 ms, `type-at` 1,250 to 1,300 ms and `refs` 1,400 ms for each; the session needs 1,200 to 2,000 ms
for the first check, about 1,150 to 1,270 ms to type, 90 to 105 ms for a hover or a definition, 230 to 245 ms for the
references and 750 ms for a workspace symbol, with 216 MB of memory (60 MB for the smaller sources).

`Analysis.refresh` relinks and checks the program of the file that changed, so typing in a file costs about what
`agentica check` does without the start of a process; what the cache saves is every question about the file after the
check. A refresh also takes longer when the cache holds another open file that imports the changed one.

## Logging

The server logs through `std/logger` to three destinations, each with its own level (`debug`, `info`, `warning` or
`error`). Nothing below the level of a destination reaches it.

| Destination | Default level | Set with |
| --- | --- | --- |
| stderr (what editors show in their LSP log) | `warning` | `--log-level`, `logLevel` |
| the editor, as `window/logMessage` notifications | `error` | `--client-log-level`, `clientLogLevel` |
| a file of JSON lines, one event per line | the level of stderr | `--log-file PATH`, with `--log-level`, `logLevel` |

- `--log-level LEVEL` sets the level of stderr and of the log file; the file has no level of its own.
- `--client-log-level LEVEL` sets the level of the log messages sent to the editor. The types are 1 (error),
  2 (warning), 3 (info) and 4 (log, for debug). The handler starts after the `initialize` request has been answered,
  so the editor gets nothing before the answer.
- `--log-format text|json` sets the format of stderr: `TIME LEVEL message key=value ...` (the default) or one JSON
  object per line. The log file is always JSON lines, appended to if it exists. A file that cannot be written is warned
  about and not used.
- The editor can set the two levels in the `initializationOptions` of `initialize`, for example
  `{"logLevel": "debug", "clientLogLevel": "info"}`. An option on the command line wins over the same setting from the
  editor.
- An invalid option (an unknown level or format, an option without a value, an unknown argument) is warned about and
  ignored, as if it was not given. A level the editor sets in `initializationOptions` then applies, or else the
  default. A level from the editor that is not valid is also warned about and ignored.

What is logged:

- `debug`: each message received and sent (the method and the id, never document text), the start and the end of
  each check with its URI, generation and duration in milliseconds, and the queries that the analysis refused.
- `info`: the start (with the `agentica` binary of the catalog), the initialization (with the position encoding), the
  loading of the builtin catalog and the shutdown.
- `warning`: a definition, references, hover, symbols or workspace symbols request whose query failed, a builtin
  catalog that could not be loaded, a URI that is not a local file, an ignored argument or a setting that is not valid.
- `error`: a crashed check task or input reader, and a message without a `Content-Length` header, which ends the
  session.

stdout carries only the protocol: the log messages for the editor are written by the main task of the server, like
the diagnostics.

## Development

```sh
make test   # agentica check, then the BDD specs in specs/ (agentica test)
```

Every scenario starts the server through the shell launcher `bin/agc-lsp` (with `env`, so on Windows through the `bash`
of Git for Windows); the program is compiled once into `$TMPDIR/agc-lsp-specs-cache` (`%TEMP%` on Windows; about 3 s)
and the next runs reuse it until the sources or `agentica` change. `make smoke` (part of `make test`) runs a whole
session (initialize, shutdown, exit) through the launcher with `specs/smoke.agc`, in the same cache folder.
`bin\agc-lsp.bat` is covered only by that smoke test, which CI runs from `cmd` on Windows (with its own cache folder),
followed by the features in `specs/` that are not in `specs/unix/`. The features in `specs/unix/` need `env`, `bash`
and `ln` (the launcher and the links) or folders called `c:` (Windows paths read on Unix), so the Windows CI skips
them. The slow checks and queries of the scenarios come from a module of thousands of functions that the file imports.

## License

Licensed under the [Apache License 2.0](LICENSE).
