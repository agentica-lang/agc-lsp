---
name: agentica-programming
description: >-
  Write, check, run, test and repair the Agentica code of agc-lsp (`.agc`
  sources, `.feature` BDD specs and their step programs). A proxy: it loads
  the agentica-programming skill of the Agentica repository. Use before
  writing or reviewing any `.agc` or `.feature` file here.
---

# Agentica programming (proxy)

The real skill lives in the Agentica repository, on `master`:

```sh
BASE=https://raw.githubusercontent.com/sonic182/agentica/master/.agents/skills/agentica-programming
curl -fsSL "$BASE/SKILL.md"
```

Read it and follow it as if it were this file. When it points to
`references/NAME.md`, fetch `$BASE/references/NAME.md` the same way, only the
ones the task needs (`bdd.md` for specs, `processes.md` for `Process`).

If a checkout of the Agentica repository sits at `../agentica`, read
`../agentica/.agents/skills/agentica-programming/` instead of fetching.

`master` may document builtins newer than the release CI pins
(`AGENTICA_VERSION` in `.github/workflows/ci.yml`). Use only what that release
has: `agentica help NAME` on the pinned binary is the authority on signatures.
