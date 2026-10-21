---
name: agentica-code-guidelines
description: >-
  Style and idiom for the Agentica code of agc-lsp (`.agc` sources and step
  programs): naming, layout, modules, functions, pipes, case, Result/try, docs.
  A proxy: it loads the agentica-code-guidelines skill of the Agentica
  repository. Use before writing or reviewing any `.agc` file here.
---

# Agentica code guidelines (proxy)

The real skill lives in the Agentica repository, on `master`:

```sh
BASE=https://raw.githubusercontent.com/sonic182/agentica/master/.agents/skills/agentica-code-guidelines
curl -fsSL "$BASE/SKILL.md"
```

Read it and follow it as if it were this file. When it points to
`references/NAME.md`, fetch `$BASE/references/NAME.md` the same way, only the
ones the task needs (`style.md` for bad/good examples, `performance.md` for hot
paths).

If a checkout of the Agentica repository sits at `../agentica`, read
`../agentica/.agents/skills/agentica-code-guidelines/` instead of fetching.

The people version of the rules is `site/content/style.md` of that repository.

`master` may document builtins newer than the release CI pins
(`AGENTICA_VERSION` in `.github/workflows/ci.yml`). Use only what that release
has: `agentica help NAME` on the pinned binary is the authority on signatures.
