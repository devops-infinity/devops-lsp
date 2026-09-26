# devops-lsp

A Claude Code plugin marketplace for TypeScript, JavaScript, Rust, Python, shell, and PHP language servers.

Add it once and every repository you open gets code intelligence from a real language server, plus an auto-heal layer that formats each edit and runs a whole-project check. The plugins are independent, so you install only the languages you use.

- [`typescript-lsp`](plugins/typescript-lsp/README.md): `typescript-language-server`, with `eslint --fix` after edits and a `tsc --noEmit` gate.
- [`rust-lsp`](plugins/rust-lsp/README.md): `rust-analyzer`, with `rustfmt` after edits and a `cargo clippy` gate.
- [`python-lsp`](plugins/python-lsp/README.md): `basedpyright`, with `ruff check --fix` and `ruff format` after edits and a `basedpyright` gate.
- [`shell-lsp`](plugins/shell-lsp/README.md): `bash-language-server`, with `shfmt` after edits and a `shellcheck` gate.
- [`php-lsp`](plugins/php-lsp/README.md): `intelephense`, with `php -l` plus a formatter after edits and a `PHPStan` gate.
- [`json-lsp`](plugins/json-lsp/README.md): the VS Code JSON language server, with `prettier --write` after edits and a `prettier --check` gate.
- [`yaml-lsp`](plugins/yaml-lsp/README.md): `yaml-language-server`, with `prettier --write` after edits and a `yamllint` plus `prettier --check` gate.

## Status

Seven plugins, each at version 1.0.0. The marketplace is MIT-licensed.

## Contents

- [Status](#status)
- [What you need installed](#what-you-need-installed)
- [Install](#install)
- [What Claude gets from it](#what-claude-gets-from-it)
- [The auto-heal layer](#the-auto-heal-layer)
- [NestJS and Next.js](#nestjs-and-nextjs)
- [Tuning a large repo](#tuning-a-large-repo)
- [Adding more language servers](#adding-more-language-servers)
- [Support](#support)
- [Contributing](#contributing)
- [License](#license)

## What you need installed

These plugins tell Claude Code how to reach a language server and which checks to run. They don't ship those tools, so each one must be on your `PATH`.

### For typescript-lsp

- `typescript-language-server` and `typescript`. Install them globally with Bun:

  ```sh
  bun add -g typescript-language-server@6.0.1 typescript@6.0.3
  ```

  Keep `typescript` on the 6.x line, at 6.0.3. TypeScript 7 is the native rewrite and it removed `tsserver`, the program `typescript-language-server` drives; its npm `bin` holds `tsc` alone, so installing it leaves you with no language server. The server still targets TypeScript 6 and its own install line asks for `typescript@6`, and it requires Node 22.22.2 or newer.

For the auto-heal hooks:

- `jq`, which the hooks use to read Claude's JSON from stdin. macOS: `brew install jq`. Debian or Ubuntu: `sudo apt-get install jq`.
- `node` and `npx`, which the hooks use to call each project's own `eslint` and `tsc` through `npx --no-install`. Any recent Node works.
- `git`, which the hook and the gate use to find the project root and the changed files.

Per project, not global:

- `eslint` with a config, and `typescript` with a `tsconfig.json`, as dev dependencies. The hooks use each project's own copies and skip when a project doesn't have them. Most TS projects already do.

If a tool from the first two groups is missing, install it before you rely on the plugin. The server doesn't attach without `typescript-language-server`, and the hooks no-op rather than crash when `jq`, `npx`, or `git` aren't there.

### For rust-lsp

Everything comes from rustup, in one command:

```sh
rustup component add rust-analyzer rust-src clippy rustfmt
```

- `rust-analyzer` is the server. `rust-src` is the standard-library source it reads to resolve `std` symbols; without it, `std` types do not resolve.
- `clippy` backs both the server's live diagnostics and the gate script. `rustfmt` backs the per-edit format hook.
- `jq` and `git` are needed by the hooks.

Nothing is needed per project. Cargo builds the workspace, so unlike the TypeScript plugin there's no per-project dev dependency to install.

Use the rustup component rather than the standalone weekly release from GitHub. The rustup build is compiled alongside your toolchain, so its proc-macro server always matches your compiler. The weekly build ships bug fixes sooner, but a proc-macro server that doesn't match the compiler fails quietly: it keeps running and reports macro-generated symbols as unresolved, which reads as broken code. Matching the toolchain matters more, especially in any repository with a `rust-toolchain.toml` pin.

### For python-lsp

Two tools, both from `uv`:

```sh
uv tool install basedpyright
uv tool install ruff
```

- `basedpyright` backs both the language server and the gate script. `ruff` backs the per-edit fix and format.
- `jq` and `git` are needed by the hooks.

Nothing is needed per project to make the type check run. The formatter is narrower: it only fires where a project opted into ruff, meaning a `ruff.toml`, a `.ruff.toml`, or a `[tool.ruff]` section in `pyproject.toml`. Reformatting a repository that standardized on something else would rewrite files it didn't ask to be touched.

The `pyright` package on PyPI is a wrapper that downloads a Node runtime on first run, which fails on locked-down machines and in offline containers. basedpyright ships real wheels with the server and its runtime bundled, so `uv tool install` is the whole story. To use stock pyright instead, change `command` in `plugins/python-lsp/.lsp.json` to `pyright-langserver`; the settings block works with both.

### For shell-lsp

The server from Bun, the two tools from Homebrew:

```sh
bun add -g bash-language-server@5.8.1
brew install shellcheck shfmt
```

- `bash-language-server` is the server; it shells out to `shellcheck` for diagnostics, so both must be on your `PATH`.
- `shfmt` backs the per-edit format hook. `shellcheck` also backs the gate script.
- `jq` and `git` are needed by the hooks.

On Debian or Ubuntu, `sudo apt-get install shellcheck shfmt`.

The formatter runs on every shell file Claude edits, rather than waiting for an opt-in config, because shell has no equivalent of a `[tool.ruff]` marker. It stays out of your way through `.editorconfig`: `shfmt` reads it, so a repository that declares `indent_style` or `indent_size` for `*.sh` keeps its own style.

`.zsh` is deliberately unmapped. shellcheck can't parse zsh, so pointing the server at zsh files yields parse errors rather than findings. Zsh scripts are left alone entirely.

### For php-lsp

The server from Bun, the PHP tools from Composer:

```sh
bun add -g intelephense@1.18.5
composer global require laravel/pint phpstan/phpstan
```

- `intelephense` is the server. It needs Node, not PHP.
- `php` must be on your `PATH` for the parse check. `pint` backs the fallback formatter; a project that ships its own Pint, PHP-CS-Fixer, or PHP_CodeSniffer in `vendor/bin` is used in preference.
- `phpstan` backs the gate script, again preferring the project's own copy.
- `jq` and `git` are needed by the hooks.

PHP 8.3 or newer is required.

Intelephense is proprietary freemium. The free tier covers everything an agent uses: go to definition, find references, hover, and document and workspace symbols. The paid tier gates rename, code actions, code lens, and inlay hints, features that matter in an editor and not to Claude. Nothing here requires a key, and the plugin never ships one. If you own a licence, drop it at `~/.config/intelephense/global/licence.txt` and the server picks it up.

Intelephense's diagnostics are turned off. It has no framework awareness, and on Eloquent magic methods, facades, and Filament's fluent builders it reports "undefined method" on code that is correct. PHPStan owns diagnostics instead, which keeps one owner per job and removes a large false-positive source in a single setting.

Blade is not mapped and `.inc` is not claimed. Blade's `@directive` syntax is not PHP, so handing `.blade.php` to a PHP parser produces garbage; the templates are also excluded from Intelephense's index, since its `*.php` glob would pull them in. `.inc` is used for plenty of things that are not PHP.

### For json-lsp

The server and the formatter from Bun:

```sh
bun add -g vscode-langservers-extracted@4.10.0 prettier@3.9.9
```

- `vscode-langservers-extracted` ships the VS Code JSON language server as the `vscode-json-language-server` binary. The same package also carries the HTML, CSS, ESLint, and Markdown servers, which this plugin does not use.
- `prettier` backs the per-edit format and the gate.
- `jq` and `git` are needed by the hooks.

The server validates a file against its JSON Schema and ships associations for `package.json`, `tsconfig.json`, `jsconfig.json`, `composer.json`, and `.eslintrc.json`. Unlike the YAML server it does not read the SchemaStore catalog on its own, so add any further association under `settings.json.schemas` in `plugins/json-lsp/.lsp.json`.

### For yaml-lsp

The server and the formatter from Bun, the linter from `uv`:

```sh
bun add -g yaml-language-server@1.24.0 prettier@3.9.9
uv tool install yamllint
```

- `yaml-language-server` is the server. It reads the SchemaStore catalog by filename, so a GitHub workflow, a Compose file, and a Kubernetes manifest all validate with no setup.
- `prettier` backs the per-edit format and one half of the gate. `yamllint` backs the other half.
- `jq` and `git` are needed by the hooks.

Both `.yaml` and `.yml` map to the server. `.yaml` is the extension the YAML project recommends and the one RFC 9512 lists first; `.yml` is shorter, still widely used, and dates from the years when a filename extension was limited to three characters. Both parse identically.

## Install

Install the language server first (see "What you need installed" above), then add the marketplace and install the plugins you want. Both commands run at user scope by default, which is global: the plugins auto-load in every project you open, so you set this up once per machine.

```sh
claude plugin marketplace add https://github.com/devops-infinity/devops-lsp
claude plugin install typescript-lsp@devops-lsp
claude plugin install rust-lsp@devops-lsp
claude plugin install python-lsp@devops-lsp
claude plugin install shell-lsp@devops-lsp
claude plugin install php-lsp@devops-lsp
claude plugin install json-lsp@devops-lsp
claude plugin install yaml-lsp@devops-lsp
```

They're independent, and each stays quiet in projects of the other languages, so install only the ones you want.

Restart Claude Code so the language server attaches, then confirm the plugins loaded globally:

```sh
claude plugin list
claude plugin details typescript-lsp@devops-lsp
```

`claude plugin list` shows each plugin at `Scope: user`, enabled. `details` reports one LSP server, one skill, and one hook per plugin. Keep the default scope, and pass `--scope project` only to limit a plugin to a single repository.

If the LSP tool does not appear, set `ENABLE_LSP_TOOL=1` in your environment or `settings.json` and restart. To see what loaded, run `claude --debug` and look for the line reporting how many LSP servers loaded.

## What Claude gets from it

Claude Code's LSP tool exposes nine read-only operations: go to definition, go to implementation, find references, hover, document symbols, workspace symbols, and call hierarchy (prepare, incoming, outgoing). The TypeScript, Rust, and Python servers support all nine. The shell server supports six; it has no implementations or call hierarchy, because shell has no such structure to report. The JSON and YAML servers report validation diagnostics, hover, completion, and document symbols, and they are the two that validate a file against a schema rather than only parsing it. Every server pushes its diagnostics into Claude's context, so Claude sees mistakes without being asked.

Two of those operations matter most on Rust. `hover` reports the type the compiler inferred, which is often not written anywhere in the source, because Rust elides most types. `go to implementation` finds every implementor of a trait, which are typically scattered across files that never name the trait.

The LSP can read your code, but it can't change it. Claude Code doesn't expose quick-fix, rename, or format through the language server, which is why the fixing runs through command-line tools instead.

## The auto-heal layer

Each plugin wires three pieces together: the language server for code intelligence, a `PostToolUse` hook that formats or fixes each file as Claude edits it, and a gate script that runs the authoritative whole-project check. A bundled skill teaches Claude how to use them together.

Every script is POSIX `sh`, so the same file runs under `sh`, `bash`, `zsh`, `dash`, and BusyBox `sh`. Nothing is duplicated per shell.

The hooks run per file and stay quick. The gate scripts run the whole project, which is slower, and that cost is why they ship unwired.

### typescript-lsp

- The skill `ts-autoheal` tells Claude how to work on TS/JS: check references before changing a shared signature, run `eslint --fix` and `tsc --noEmit` after editing, trust `tsc` over the pushed diagnostics when they disagree, and keep going until both are clean.
- The `PostToolUse` hook runs `eslint --fix` on each TS/JS file Claude writes or edits, then hands any leftover lint back to Claude. It fires only in projects that have an ESLint config, and it is quick because it runs on the single file.
- The gate script `plugins/typescript-lsp/scripts/ts-gate.sh` runs a full `tsc --noEmit`. It probes `tsc` first and blocks when it cannot run, so a check that never happened is not read as a pass.

### rust-lsp

- The skill `rust-autoheal` tells Claude how to work on Rust: hover to read inferred types, check implementors before changing a trait, run `cargo clippy` after editing, and fix causes rather than covering them with `.clone()`, `unwrap()`, or `#[allow(...)]`.
- The `PostToolUse` hook runs `rustfmt` on each `.rs` file Claude writes or edits. It reads the crate's edition out of `Cargo.toml` first and passes it through, which matters: bare `rustfmt` assumes edition 2015 and fails on any file with an `async fn`, leaving it unformatted with nothing to say so. Workspace members that inherit `edition.workspace = true` are handled by walking up to `[workspace.package]`. If `rustfmt` reports an error, the file does not parse, and that error goes back to Claude.
- The gate script `plugins/rust-lsp/scripts/rust-gate.sh` runs `cargo clippy --workspace --all-targets`. Clippy is a superset of `cargo check`: it does the full type and borrow check plus the lints in one pass, so one invocation covers both jobs. It blocks on errors only and reports the warning count alongside. It also blocks when clippy cannot run for a workspace, so a check that never happened is not read as a pass. To block on warnings too, add `--deny warnings` to the clippy call in the script.

Rust makes it easy to run the same compile several times per edit, so each job has exactly one owner:

- Formatting is `rustfmt`, per file, on edit. Nothing else formats.
- Symbol intelligence is rust-analyzer: hover, definitions, references, implementors. It spawns no build you wait on.
- The authoritative check is `cargo clippy`, once, at the end of the turn. Nothing else compiles.

If you also run a personal `PostToolUse` hook that formats or checks Rust, remove its Rust branch when you install this plugin, or you get two formatters and an extra full compile on every edit.

rust-analyzer's compiler diagnostics come from `cargo`, and `cargo` re-runs on save. Claude Code writes files without necessarily sending the editor a save notification, so those diagnostics may not refresh after an edit. That's why the bundled skill tells Claude to run clippy itself rather than wait to be told. Turning on `diagnostics.experimental.enable` adds live type-mismatch hints at the cost of false positives; it's off on purpose.

Both Rust hooks skip quietly, and fast, in three cases: outside a Cargo project, when `rustfmt` or `cargo` is not callable, and when a toolchain file pins a version that is not installed.

The last case matters because `cargo`, `rustfmt`, and even `rustup toolchain list` resolve the active toolchain from the current directory, and running one inside a project pinned to an uninstalled toolchain makes rustup download it, about a gigabyte, with no prompt, inside a hook. The guard therefore reads the filesystem only: it walks up for `rust-toolchain.toml` or a bare `rust-toolchain` file, reads the channel, and checks `~/.rustup/toolchains` directly.

The gate finds its work from the changed files rather than assuming a layout, so a Cargo project nested anywhere in the repository is covered: `services/api/Cargo.toml` in a monorepo with no root manifest works, and several separate workspaces in one repository each get checked. It runs only inside a git repository with uncommitted `.rs` changes.

### python-lsp

- The skill `python-autoheal` tells Claude how to work on Python: hover to read the inferred type rather than trusting an annotation that may be absent or wrong, check references before changing a signature (Python resolves names at runtime, so nothing else catches a missed caller), and fix causes instead of reaching for `# type: ignore`, `Any`, or a `cast()`.
- The `PostToolUse` hook runs `ruff check --fix` and then `ruff format` on each edited file, in that order, and hands back whatever ruff could not fix. It fires only in projects that opted into ruff.
- The gate script `plugins/python-lsp/scripts/python-gate.sh` runs `basedpyright` across each touched project. Like the Rust gate, it resolves projects from the changed files (`pyproject.toml`, `setup.py`, or `setup.cfg`), so a package nested in a monorepo is covered.

The server runs in `openFilesOnly` mode, so it reports nothing about files Claude has not opened. A change that breaks a caller three modules away stays invisible until the gate runs. That keeps the live path fast and leaves whole-project truth to the gate. It is also the safer choice here: workspace mode has a maintainer-acknowledged bug where it re-analyzes the whole project on every change.

Four details in this plugin are worth knowing:

- The interpreter is passed explicitly. basedpyright looks for `./.venv` relative to the project root and ignores `VIRTUAL_ENV` completely, so a wrong pick makes every third-party import resolve to nothing. The gate finds the venv itself and passes `--pythonpath`.
- A failed run can look clean. Point basedpyright at a path that does not exist and it writes zero bytes to stdout and exits 4. A gate that only reads stdout finds no errors and passes. This gate treats any exit above 1, or any output without a `summary` key, as unverified rather than clean.
- A rejected config is nearly silent. A one-character typo in `typeCheckingMode` writes a line to stderr, still emits valid JSON on stdout, and quietly reverts to a different checking mode. The gate captures stderr and reports configuration rejection as a blocking condition.
- Settings are sent twice, on purpose. The server reads analysis settings from `basedpyright.analysis`, falling back to `python.analysis` through an undocumented compatibility path the official docs call unsupported. Both are sent so neither route can leave the config unapplied. `initializationOptions` is deliberately absent: the server reads no analysis settings from it, so a block there would be dead config.

`disableTaggedHints` is on. Without it the server pushes hint-severity "unnecessary code" diagnostics that the CLI never reports, which burn context and prompt the model to "fix" code that is fine.

### shell-lsp

- The skill `shell-autoheal` tells Claude how to work on shell: quote every expansion, do not parse `ls`, know what `set -euo pipefail` does not cover, and never cover a finding with a bare `# shellcheck disable=`.
- The `PostToolUse` hook applies `shellcheck --format=diff` and then runs `shfmt --write`. The fix step is safe to run unattended: shellcheck emits a replacement only where the correction is unambiguous, quoting an expansion or adding `|| exit` after a bare `cd`, and leaves anything requiring judgement untouched.
- The gate script `plugins/shell-lsp/scripts/shell-gate.sh` runs `shellcheck` over the changed shell files and reports `error`, `warning`, and `info`. Only `style` is advisory.

That threshold is not the obvious choice. shellcheck's severity tiers do not line up with how dangerous a defect is. `rm -rf $var/`, which wipes the filesystem when the variable is empty, is only a `warning` (SC2115). A `cd` that failed and let the script keep deleting in the wrong directory is also only a `warning` (SC2164). Unquoted expansion, a common real bug in shell, is merely `info` (SC2086). An error-only gate ships all three.

Two other things this gate does:

- It checks shellcheck's exit code, not just its output. Codes 2, 3, and 4 mean the scan never ran: an unreadable file, a bad invocation, an unknown flag. Those block with their own message, because reporting "no findings" from a scan that did not happen is misleading.
- It matches files by shebang as well as extension, so a `pre-commit` hook or an extensionless CLI entry point is covered rather than silently skipped.

It also avoids `--severity=info` as the filter mechanism. Passing that flag makes shellcheck emit an empty comment list and exit 0, which is indistinguishable from a clean file. Severity is filtered after the fact instead, where an empty result still carries meaning.

Background analysis is off (`backgroundAnalysisMaxFiles: 0`, `includeAllWorkspaceSymbols: false`). Workspace-wide symbol indexing serves completion, hover documentation, and rename, none of which an agent consuming diagnostics uses, and it is the driver behind several upstream reports of the server using excess CPU and memory. Per-file diagnostics run on a separate path and are unaffected.

bash-language-server 5.8.1 is the npm release this plugin pins. It passes `--external-sources` to shellcheck unconditionally with no way to turn it off. The plugin absorbs that by excluding SC1091, so unresolvable `source` paths cannot block the gate.

### php-lsp

- The skill `php-autoheal` tells Claude how to work on PHP: check references before changing a signature, never run PHPStan without a level, and do not silence findings with `@phpstan-ignore` or by widening a type to `mixed`.
- The `PostToolUse` hook runs `php -l` first and stops there if the file does not parse, then runs whichever formatter the project configured. The detection order is `pint.json` or `vendor/bin/pint`, then `.php-cs-fixer.php` or `.php-cs-fixer.dist.php`, then `phpcs.xml` or `phpcs.xml.dist` (running `phpcbf`), then Pint's default preset as a fallback. Exactly one runs.
- The gate script `plugins/php-lsp/scripts/php-gate.sh` runs PHPStan across every touched project.

Three details are worth knowing:

- PHPStan with no config runs at level 0 and passes. Level 0 catches almost nothing: on a function declared `: int` that returns a string, level 0 reports zero errors and level 5 catches it. So when a project has no `phpstan.neon`, the gate passes `--level=5` explicitly and says so in its output rather than letting a meaningless clean result through.
- `php -l` exits 255 on a parse error, not 1. A hook checking `-eq 1` would miss every syntax error.
- Pint ignores `--format` under Claude Code. It emits its own agent-shaped JSON regardless of the format requested, so the hook reads that shape instead of fighting it. `--repair` exits 1 when it changed something and 0 when it did not.

PHP-CS-Fixer is always invoked with `--path-mode=intersection`. Its default, `override`, makes an explicit file path ignore the config's own `Finder`, so a per-file hook would reformat files the project deliberately excluded.

Rector is deliberately absent. It rewrites semantics rather than formatting, needs a project-specific `rector.php` to do anything useful, and its workflow is dry-run, review the diff, run the tests. None of that fits inside a hook that fires after every edit.

### json-lsp

- The skill `json-autoheal` tells Claude how to work on JSON: read the file's schema before editing, never add a `$schema` key just to get validation, and keep a `.json` file free of comments and trailing commas.
- The `PostToolUse` hook runs `prettier --write` on each `.json` and `.jsonc` file Claude writes or edits, using the project's own Prettier when it has one.
- The gate script `plugins/json-lsp/scripts/json-gate.sh` runs `prettier --check` over the changed files. It fails on a file that does not parse and on one that is not canonically formatted, so one command covers both.

### yaml-lsp

- The skill `yaml-autoheal` tells Claude how to work on YAML: quote a value that could be read as another type, keep to two-space indentation, and never keep a `.yaml` and a `.yml` for the same file.
- The `PostToolUse` hook runs `prettier --write` on each `.yaml` and `.yml` file Claude writes or edits.
- The gate script `plugins/yaml-lsp/scripts/yaml-gate.sh` runs `yamllint` and then `prettier --check` over the changed files. yamllint uses the project's own `.yamllint` when it has one, and otherwise a Prettier-compatible default, because the stock rules want two spaces before an inline comment and a `---` document start, and Prettier writes neither. A yamllint that fails to run blocks rather than reading as clean.

### The gates are not wired up

Every plugin ships a gate script, `plugins/<name>/scripts/<name>-gate.sh`, that runs the authoritative whole-project check. None of them is registered as a `Stop` hook. They exist to be run, by Claude following its skill, or by you from the command line. Nothing blocks a turn.

A `Stop` hook fires at the end of every turn in every repository you open, because these plugins are global. A whole-project `tsc --noEmit` can take a minute, a cold `cargo clippy` several, and PHPStan with Larastan boots the Laravel container, so a project whose service providers touch a database or a queue would pay that on every turn.

So the check sits with the model rather than with a hook. Each skill says plainly that nothing catches the mistake for it, and to run the check itself before calling the work done.

To enforce a gate on a project or a machine, add the `Stop` block back to that plugin's `hooks/hooks.json`:

```json
"Stop": [
  {
    "hooks": [
      { "type": "command", "command": "\"${CLAUDE_PLUGIN_ROOT}\"/scripts/rust-gate.sh", "timeout": 600 }
    ]
  }
]
```

Keep the timeout generous, 600 seconds for the compiled languages, since the 60-second default isn't enough for a cold build.

To run one by hand, feed it the JSON a hook would receive:

```sh
echo '{"stop_hook_active":false}' | plugins/rust-lsp/scripts/rust-gate.sh
```

It prints a JSON block describing what it found, or nothing at all when the project is clean.

## NestJS and Next.js

NestJS and plain TS/JS projects work as-is. The server reads each project's `tsconfig.json`.

Next.js needs one extra step to get its own diagnostics: the App Router route checks, the `'use client'` rules, and typed routes. List the Next plugin in the project's `tsconfig.json` under `"plugins": [{ "name": "next" }]`, keep `.next/types/**/*.ts` in the `include` array, and run `next dev`, `next build`, or `next typegen` once so the generated types exist. The server uses the workspace TypeScript, so the Next plugin loads with it.

## Tuning a large repo

The TypeScript server's memory ceiling lives in `plugins/typescript-lsp/.lsp.json` as `maxTsServerMemory`, in megabytes. It's a ceiling, not a reservation, so the default of 8192 is safe on small projects and gives a large monorepo headroom. Lower it if you're tight on RAM.

To quiet noisy diagnostics, add the TypeScript error codes you want to mute to `settings.diagnostics.ignoredCodes` in the same file.

On the Rust side the knobs are in `plugins/rust-lsp/.lsp.json`. Memory scales with crate count, not with these settings: expect around 1 GB on a small project, and a large workspace can run many times that. In rough order of what to reach for first:

- `cachePriming.enable`, set to `false` to cut the indexing burst at startup. This shortens time-to-ready; it doesn't reduce steady-state memory.
- `lru.capacity`, the number of syntax trees held in memory, 128 by default. Lowering it trades memory for recomputation.
- `files.exclude`, to add generated or vendored directories. This removes them from the index, so it cuts memory and stops Claude from finding and editing generated code.
- `numThreads`, a rust-analyzer setting that caps CPU rather than memory. Add it to the same file if you need it.

Two settings look tempting and are traps. Turning off `procMacro.enable` or `cargo.buildScripts.enable` makes startup much faster and breaks every symbol a derive or attribute macro generates: `#[derive(Serialize)]`, `#[tokio::main]`, `clap::Parser`, `async_trait`. They don't error; they resolve to nothing, and Claude reads that as broken code. Leave both on.

If clippy proves slow or noisy on a particular repository, change `check.command` from `"clippy"` to `"check"` in the same file. That keeps live type errors and drops the lints.

Settings in that file must be nested objects with the `rust-analyzer.` prefix stripped, for example `{"check": {"command": "clippy"}}`. Flat dotted keys like `{"check.command": "clippy"}` are silently ignored: no error, no warning, the setting never applies.

The JSON and YAML server settings live in `plugins/json-lsp/.lsp.json` and `plugins/yaml-lsp/.lsp.json`. The JSON file holds its schema associations under `settings.json.schemas`. The YAML file holds `settings.yaml.schemas` and leaves the SchemaStore catalog on, which it is by default; set `schemaStore.enable` to `false` to stop the server fetching remote schemas on a locked-down machine.

## Adding more language servers

The marketplace holds more than one plugin. To add a Go or Ruby server, for example:

1. Create `plugins/<name>/.claude-plugin/plugin.json` with the metadata and an `lspServers` pointer.
2. Add `plugins/<name>/.lsp.json` with the server's command and extension mapping.
3. Add an entry to `.claude-plugin/marketplace.json` with `source` pointing at that folder.
4. List the server's install command in this file.

Write the new plugin's two scripts as POSIX `sh`, matching the existing ones, so they run under any shell.

## Support

Open an issue at https://github.com/devops-infinity/devops-lsp.

## Contributing

Pull requests are welcome at https://github.com/devops-infinity/devops-lsp.

## License

MIT, copyright DevOps. See [LICENSE](LICENSE).
