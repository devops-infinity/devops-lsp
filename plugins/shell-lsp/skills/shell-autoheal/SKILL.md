---
name: shell-autoheal
description: Auto-heal shell scripts after edits. Use when editing, refactoring, or reviewing .sh, .bash, or .bats files, when shellcheck or shfmt reports problems, or when asked to fix, clean up, format, or lint a bash or POSIX shell script.
---

# Shell auto-heal

You have a shell language server (bash-language-server), and it's read-only. It can look things up — goToDefinition, findReferences, hover, documentSymbol, workspaceSymbol, and completion — and it surfaces shellcheck diagnostics for open files. It does not provide implementations or call hierarchy, because shell has no such structure. What it can't do is change code. You do the fixing with the command-line tools below.

## Before you edit

- Hover a builtin or a command to read its documentation instead of guessing at flag behavior.
- Use goToDefinition on a function to find where it's defined; in a large script the definition is often far from the call.
- Before you rename or change a function's arguments, run findReferences. Shell has no compiler, so a missed call site fails at runtime, usually in production.

## After you edit, fix it — don't just report it

- Formatting is already handled. A PostToolUse hook runs `shfmt --write` on each file you edit, and it honors the project's `.editorconfig`, so indentation follows the repo rather than a default.
- Run `shellcheck <file>` for the real check. It catches quoting bugs, unset-variable hazards, and misuse that no formatter sees.
- Fix by severity: `error` first (those break the script), then `warning`, then `info`. The Stop gate blocks only on `error`, but warnings are usually genuine bugs waiting for the wrong input.

## The bugs that actually bite

- Quote every expansion unless you have a specific reason not to: `"$var"`, `"$@"`, `"${arr[@]}"`. Unquoted expansion word-splits and glob-expands, which is the single most common shell bug, and it stays invisible until a path contains a space.
- Don't parse `ls`. Use a glob or `find -print0` with `read -d ''`.
- Set `set -euo pipefail` in new scripts, and know what it doesn't cover: `-e` is ignored inside conditions and in most command substitutions.
- Check that a variable is set before using it under `set -u`, with `"${var:-}"` when it's genuinely optional.
- Never silence a finding with a `# shellcheck disable=` comment unless you can say in one sentence why the tool is wrong here. Add the specific code, never a bare disable.

## You're done when

`shellcheck` reports no errors on the files you touched. A Stop hook runs it before the turn can end, so this isn't optional. Clear the warnings too — in shell they are usually real defects, not style.
