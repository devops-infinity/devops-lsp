---
name: shell-notify
description: Work on shell scripts with the language server and the project's own checks. Use when editing, refactoring, or reviewing .sh, .bash, or .bats files, when shellcheck reports problems, or when asked to fix, lint, or check a bash or POSIX shell script.
---

# Shell notify

You have a shell language server (bash-language-server), and it's read-only. It can look things up (goToDefinition, findReferences, hover, documentSymbol, workspaceSymbol, and completion), and it surfaces shellcheck diagnostics for open files. It does not provide implementations or call hierarchy, because shell has no such structure. What it can't do is change code. Nothing fixes anything for you. The checks report the failures, and the fixing is yours.

## Before you edit

- Hover a builtin or a command to read its documentation instead of guessing at flag behavior.
- Use goToDefinition on a function to find where it's defined; in a large script the definition is often far from the call.
- Before you rename or change a function's arguments, run findReferences. Shell has no compiler, so a missed call site fails at runtime, usually in production.

## After you edit

- A PostToolUse hook runs `shellcheck` on each file you edit and reports its error, warning, and info findings back to you. It never modifies the file, so fix what it reports with your own edits. It does not format: when the project expects it, run `shfmt` yourself, and note that `shfmt` reads `.editorconfig`, so a repository that declares `indent_style` or `indent_size` for `*.sh` keeps its own style.
- Fix by severity: `error` first (those break the script), then `warning`, then `info`. All three are reported, because warnings are usually genuine bugs waiting for the wrong input.

## The bugs that actually bite

- Quote every expansion unless you have a specific reason not to: `"$var"`, `"$@"`, `"${arr[@]}"`. Unquoted expansion word-splits and glob-expands, which is the single most common shell bug, and it stays invisible until a path contains a space.
- Don't parse `ls`. Use a glob or `find -print0` with `read -d ''`.
- Set `set -euo pipefail` in new scripts, and know what it doesn't cover: `-e` is ignored inside conditions and in most command substitutions.
- Check that a variable is set before using it under `set -u`, with `"${var:-}"` when it's genuinely optional.
- Never silence a finding with a `# shellcheck disable=` comment unless you can say in one sentence why the tool is wrong here. Add the specific code, never a bare disable.

## You're done when

`shellcheck` reports no errors on the files you touched. Clear the warnings and info findings too: in shell those are usually real defects, not style. `rm -rf $var/` and a `cd` that failed are only warnings; unquoted expansion is only info.

**Nothing checks this for you.** There is no gate at the end of the turn. Run `shellcheck` yourself and treat its output as the verdict.
