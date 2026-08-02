# devops-lsp

A small marketplace of Claude Code language-server plugins, kept under the DevOps brand. Add it once and Claude Code gets real code intelligence, plus an auto-heal layer, in every repo you open — a NestJS API, a Next.js app, a Cargo workspace, a Python service, or anything else built on TS/JS, Rust, or Python.

All three plugins follow the same shape. Each one wires up a language server so Claude resolves definitions, references, hovers, symbols, and call hierarchy from the type system instead of guessing from text. Each one adds an auto-heal layer: a fast formatter or fixer after every edit, and a whole-project check that won't let a turn end while errors remain. Each one bundles a skill that teaches Claude how to use the two together.

- `typescript-lsp` — `typescript-language-server`, with `eslint --fix` after edits and a `tsc --noEmit` gate.
- `rust-lsp` — `rust-analyzer`, with `rustfmt` after edits and a `cargo clippy` gate.
- `python-lsp` — `basedpyright`, with `ruff check --fix` and `ruff format` after edits and a `basedpyright` gate.

## What you need installed

These plugins tell Claude Code how to reach a language server and which checks to run. They don't ship those tools, so they need to be on your PATH. Here is the full list and how to get each one.

### For typescript-lsp

- `typescript-language-server` and `typescript`. Install them globally with Bun:
  ```sh
  bun add -g typescript-language-server@5.3.0 typescript@6.0.3
  ```
  Both are the newest usable releases as of August 2nd 2026, but do not blindly bump `typescript` to 8 or to the 7.x line. TypeScript 7 is the native rewrite and it **removed `tsserver`**, which is the program `typescript-language-server` drives — its npm `bin` now contains `tsc` alone. Installing it silently leaves you with no language server. The native replacement ships as `@typescript/native-preview` and is still a dev build, so there is nothing stable to move to yet. Stay on the 6.x line (6.0.3 is the newest 6.x) until `typescript-language-server` ships support for the native server, or until this plugin is repointed at it. `typescript-language-server` itself is safe to bump; 5.3.0 is current.

For the auto-heal hooks:

- `jq` — the hooks read Claude's JSON from stdin with it. macOS: `brew install jq`. Debian or Ubuntu: `sudo apt-get install jq`.
- `node` and `npx` — the hooks call each project's local `eslint` and `tsc` through `npx --no-install`. Any recent Node works.
- `git` — the type-check gate only runs when you have uncommitted TS changes, which it checks with `git status`. Outside a git repo, the gate skips quietly.

Per project, not global:

- `eslint` with a config, and `typescript` with a `tsconfig.json`, as dev dependencies. The hooks use each project's own copies and skip cleanly when a project doesn't have them. Most TS projects already do.

If a tool from the first two groups is missing, install it before you rely on the plugin. The server won't attach without `typescript-language-server`, and the hooks no-op (rather than crash) when `jq`, `npx`, or `git` aren't there.

### For rust-lsp

Everything comes from rustup, in one command:

```sh
rustup component add rust-analyzer rust-src clippy rustfmt
```

- `rust-analyzer` is the server. `rust-src` is the standard-library source it reads to resolve `std` symbols; without it, `std` types don't resolve.
- `clippy` backs both the server's live diagnostics and the Stop gate. `rustfmt` backs the per-edit format hook.
- `jq` and `git` are needed by the hooks, same as the TypeScript plugin.

Nothing is needed per project. Cargo already knows how to build the workspace, so unlike the TS side there's no per-project dev dependency to install.

**Which rust-analyzer build to use.** Two exist, and the rustup component above is the right default. It's built alongside your toolchain, so its proc-macro server always matches your compiler. The alternative is the standalone weekly release from GitHub, which ships bug fixes far sooner — as of August 2nd 2026 the standalone was `0.3.2989` (tagged 2026-07-27) while the rustup component on stable 1.97.1 carried rust-analyzer code from mid-May, roughly eleven weeks behind.

Take the staleness anyway. A proc-macro server that doesn't match the compiler doesn't fail loudly — it keeps running and reports macro-generated symbols as unresolved. Claude reads that as broken code and "fixes" things that were never wrong. Matching the toolchain matters more than the fixes, especially in any repo with a `rust-toolchain.toml` pin. If you do want the weekly build, install it from the project's releases page and keep it off pinned repos.

### For python-lsp

Two tools, both from `uv`:

```sh
uv tool install basedpyright
uv tool install ruff
```

- `basedpyright` backs both the language server and the Stop gate. `ruff` backs the per-edit fix and format.
- `jq` and `git` are needed by the hooks, same as the other plugins.

Nothing is needed per project to make the type check run. The formatter is deliberately narrower: it only fires where a project opted into ruff, meaning a `ruff.toml`, a `.ruff.toml`, or a `[tool.ruff]` section in `pyproject.toml`. Reformatting a repo that standardized on something else would rewrite files nobody asked us to touch.

**Why basedpyright and not stock pyright.** They are the same engine — basedpyright 1.39.9 is built on pyright 1.1.411 — but they ship differently. The `pyright` package on PyPI is a wrapper that downloads a Node runtime on first run, which fails on locked-down machines and in offline containers. basedpyright ships real wheels with the server and its runtime bundled, so `uv tool install` is the whole story. It also fixes pyright behaviors that only exist to serve the VS Code extension. If you prefer stock pyright, change `command` in `plugins/python-lsp/.lsp.json` to `pyright-langserver`; the settings block is compatible with both.

## Install

Install the language server first (the "What you need installed" section above covers it), then add the marketplace and install the plugin. Both commands run at user scope by default, which is global: the plugin auto-loads in every project you open, so you set this up once per machine.

```sh
claude plugin marketplace add https://github.com/devops-infinity/devops-lsp
claude plugin install typescript-lsp@devops-lsp
claude plugin install rust-lsp@devops-lsp
claude plugin install python-lsp@devops-lsp
```

Install only the ones you want — they're independent, and each stays quiet in projects of the other languages.

Restart Claude Code so the language server attaches, then confirm it loaded globally:

```sh
claude plugin list
claude plugin details typescript-lsp@devops-lsp
claude plugin details rust-lsp@devops-lsp
claude plugin details python-lsp@devops-lsp
```

`claude plugin list` should show each plugin at `Scope: user`, enabled. `details` should report one LSP server, one skill, and two hooks per plugin. Keep the default scope — don't pass `--scope project` unless you want a plugin limited to a single repo, since they're built to be global.

If the LSP tool doesn't show up, set `ENABLE_LSP_TOOL=1` in your environment or `settings.json` and restart; some Claude Code builds need that flag even though it's meant to be on by default. To see what loaded, run `claude --debug` and look for the line reporting how many LSP servers loaded.

## What Claude gets from it

Claude Code's LSP tool exposes nine read-only operations, and these plugins make all of them work: go to definition, go to implementation, find references, hover, document symbols, workspace symbols, and call hierarchy (prepare, incoming, outgoing). The servers also push type and lint errors into Claude's context right after each edit, so Claude sees mistakes without being asked.

Two of those operations earn their keep especially well on Rust. `hover` reports the type the compiler inferred, which usually isn't written anywhere in the source — Rust elides most types, so this is information Claude cannot get by reading the file. And `go to implementation` finds every implementor of a trait, which are typically scattered across files that never name the trait, and which all break together when the trait changes.

Worth being clear about one limit: the LSP can read your code, but it can't change it. Claude Code doesn't expose quick-fix, rename, or format through the language server. That's why the fixing runs through command-line tools instead.

## The auto-heal layer

Three pieces work together.

- A skill, `ts-autoheal`, tells Claude how to work on TS/JS: check references before changing a shared signature, run `eslint --fix` and `tsc --noEmit` after editing, trust `tsc` over the pushed diagnostics when they disagree, and keep going until both are clean.
- A `PostToolUse` hook runs `eslint --fix` on each TS/JS file Claude writes or edits, then hands any leftover lint back to Claude. It only fires in projects that have an ESLint config, and it's quick because it runs on the single file.
- A `Stop` hook runs a full `tsc --noEmit` before Claude is allowed to finish. If the project doesn't type-check, Claude is sent back to fix it. To stay out of the way, this gate only runs inside a git repo that has a `tsconfig.json` and uncommitted TS changes.

A note on speed, since this is a global plugin. A whole-project `tsc --noEmit` can take anywhere from a second to a minute on a large codebase, and the `Stop` gate runs it at the end of any turn where you have uncommitted TS changes. If that's too heavy for a given machine or repo, delete the `Stop` block from `plugins/typescript-lsp/hooks/hooks.json`, or remove the hook entirely. You keep the fast per-edit `eslint --fix` and the skill guidance, and per-edit type feedback still arrives for free through the server's pushed diagnostics.

### The Rust side

The same three pieces, with the Rust tools.

- A skill, `rust-autoheal`, tells Claude how to work on Rust: hover to read inferred types, check implementors before changing a trait, run `cargo clippy` after editing, and fix causes rather than papering over them with `.clone()`, `unwrap()`, or `#[allow(...)]`.
- A `PostToolUse` hook runs `rustfmt` on each `.rs` file Claude writes or edits. It reads the crate's edition out of `Cargo.toml` first and passes it through, which matters: bare `rustfmt` assumes edition 2015 and simply fails on any file with an `async fn`, leaving it unformatted with nothing to say so. Workspace members that inherit `edition.workspace = true` are handled by walking up to `[workspace.package]`. If `rustfmt` reports an error, the file doesn't parse, and that error goes back to Claude.
- A `Stop` hook runs `cargo clippy --workspace --all-targets` before Claude can finish, and blocks while any error remains. Clippy is a superset of `cargo check` — it does the full type and borrow check plus the lints in one pass — so one invocation covers both jobs. It blocks on errors only, and reports the warning count alongside. To block on warnings too, add `--deny warnings` to the clippy call in `plugins/rust-lsp/scripts/rust-gate.sh`.

### The Python side

The same three pieces again.

- A skill, `python-autoheal`, tells Claude how to work on Python: hover to read the inferred type rather than trusting an annotation that may be absent or wrong, check references before changing a signature (Python resolves names at runtime, so nothing else will catch a missed caller), and fix causes instead of reaching for `# type: ignore`, `Any`, or a `cast()`.
- A `PostToolUse` hook runs `ruff check --fix` and then `ruff format` on each edited file, in that order, and hands back whatever ruff could not fix. It fires only in projects that opted into ruff.
- A `Stop` hook runs `basedpyright` across each touched project and blocks while any error remains. Like the Rust gate, it resolves projects from the changed files — `pyproject.toml`, `setup.py`, or `setup.cfg` — so a package nested in a monorepo is covered.

One asymmetry worth knowing: the server runs in `openFilesOnly` mode, so it reports nothing about files Claude has not opened. A change that breaks a caller three modules away stays invisible until the gate runs. That keeps the live path fast and leaves whole-project truth to the gate, which is the same split the other two plugins use.

### One checker per job

Rust makes it easy to end up running the same compile three or four times per edit — a format hook, a per-edit `cargo check`, the server's own `cargo clippy`, and a gate. That's slow, and the duplicated output teaches Claude to skim past it. This plugin deliberately assigns each job exactly one owner:

- Formatting is `rustfmt`, per file, on edit. Nothing else formats.
- Symbol intelligence is rust-analyzer: hover, definitions, references, implementors. It spawns no build of its own that you wait on.
- The authoritative check is `cargo clippy`, once, at the end of the turn. Nothing else compiles.

If you also run a personal `PostToolUse` hook that formats or checks Rust, remove its Rust branch when you install this plugin — otherwise you get two formatters and an extra full compile on every edit.

One caveat, measured rather than assumed. rust-analyzer's compiler diagnostics come from `cargo`, and `cargo` re-runs on save. Claude Code writes files without necessarily sending the editor "save" notification, so those diagnostics may not refresh after an edit. Tested directly: a type error introduced through a `didChange` with no `didSave` was reported by nothing — flycheck never re-ran, and native type-mismatch is an experimental diagnostic that's off by default here because it misfires. That is exactly why the Stop gate exists and why the bundled skill tells Claude to run clippy itself rather than wait to be told. Turning on `diagnostics.experimental.enable` buys live type-mismatch hints at the cost of false positives; it's off on purpose.

Both Rust hooks skip quietly, and fast, in three cases: outside a Cargo project, when `rustfmt` or `cargo` isn't callable, and when a toolchain file pins a version that isn't installed.

That last one is worth explaining, because getting it wrong is expensive. `cargo`, `rustfmt`, and even `rustup toolchain list` are rustup shims, and every one of them resolves the active toolchain from the current directory. Run any of them inside a project pinned to a toolchain you don't have, and rustup downloads it right there — about a gigabyte, with no prompt, inside a hook. So the guard reads the filesystem only: it walks up for `rust-toolchain.toml` or a legacy bare `rust-toolchain` file, reads the channel, and checks `~/.rustup/toolchains` directly. It never invokes rustup, and it runs before anything else. The tool-availability probes run from `/` for the same reason.

The gate finds its work from the changed files rather than assuming a layout, so a Cargo project nested anywhere in the repo is covered — `services/api/Cargo.toml` in a monorepo with no root manifest works, and several separate workspaces in one repo each get checked. It still only runs inside a git repo with uncommitted `.rs` changes. Its hook timeout is 600 seconds, because a cold `cargo clippy` on a large workspace blows straight past the 60-second default. To drop the gate, delete the `Stop` block from `plugins/rust-lsp/hooks/hooks.json`.

## NestJS and Next.js

NestJS and plain TS/JS projects work as-is. The server reads each project's `tsconfig.json`.

Next.js needs one extra step to get its own diagnostics — the App Router route checks, the `'use client'` rules, and typed routes. List the Next plugin in the project's `tsconfig.json` under `"plugins": [{ "name": "next" }]`, keep `.next/types/**/*.ts` in the `include` array, and run `next dev`, `next build`, or `next typegen` once so the generated types exist. The server uses the workspace TypeScript, so the Next plugin loads with it.

## Tuning a large repo

The server's memory ceiling lives in `plugins/typescript-lsp/.lsp.json` as `maxTsServerMemory`, in megabytes. It's a ceiling, not a reservation, so the default of 8192 is safe on small projects and gives a large monorepo headroom before it runs out of memory. Lower it if you're tight on RAM.

To quiet stale or noisy diagnostics, add the TypeScript error codes you want to mute to `settings.diagnostics.ignoredCodes` in the same file.

On the Rust side the knobs are in `plugins/rust-lsp/.lsp.json`. Memory scales with crate count, not with these settings — expect around 1 GB on a small project, and a genuinely large workspace can run many times that. In rough order of what to reach for first:

- `cachePriming.enable` — set it to `false` to cut the indexing burst at startup. This shortens time-to-ready; it doesn't reduce steady-state memory.
- `lru.capacity` — the number of syntax trees held in memory, 128 by default. Lowering it trades memory for recomputation.
- `files.exclude` — add generated or vendored directories. This genuinely removes them from the index, so it cuts memory and stops Claude from finding and editing generated code.
- `numThreads` — caps CPU rather than memory.

Two settings look tempting here and are traps. Turning off `procMacro.enable` or `cargo.buildScripts.enable` makes startup much faster, and breaks every symbol that a derive or attribute macro generates — `#[derive(Serialize)]`, `#[tokio::main]`, `clap::Parser`, `async_trait`. They don't error; they just resolve to nothing, and Claude reads that as broken code. Leave both on.

If clippy proves slow or noisy on a particular repo, change `check.command` from `"clippy"` to `"check"` in the same file. That keeps live type errors and drops the lints.

One shape note, if you edit that file: settings must be nested objects with the `rust-analyzer.` prefix stripped — `{"check": {"command": "clippy"}}`. Flat dotted keys like `{"check.command": "clippy"}` are silently ignored. No error, no warning, the setting just never applies. Both forms were tested against the installed server; only the nested one takes effect.

## Adding more language servers

The marketplace is built to hold more than one. To add a Go or Ruby server, for example:

1. Create `plugins/<name>/.claude-plugin/plugin.json` with the metadata and an `lspServers` pointer.
2. Add `plugins/<name>/.lsp.json` with the server's command and extension mapping.
3. Add an entry to `.claude-plugin/marketplace.json` with `source` pointing at the new folder.
4. List the server's install command in this file so the next person knows what to install.

## License

MIT, copyright DevOps. Change it in `LICENSE` and the manifests if you'd prefer something else.
