---
name: ts-notify
description: Work on TypeScript and JavaScript with the language server and the project's own checks. Use when editing, refactoring, or reviewing .ts/.tsx/.js/.jsx/.mts/.cts files, when type or lint errors show up, or when asked to fix, lint, or type-check TS/JS.
---

# TypeScript / JavaScript notify

You have a TypeScript/JavaScript language server, and it's read-only. It can look things up (goToDefinition, goToImplementation, findReferences, hover, documentSymbol, workspaceSymbol, and call hierarchy), and it pushes type and lint errors into your context right after each edit. What it can't do is change code: no quick fixes, no rename, no organize-imports, no formatting. Nothing fixes anything for you. The checks report the failures, and the fixing is yours.

## Before you edit

- Look a symbol up with goToDefinition or documentSymbol instead of guessing its shape.
- Before you touch an exported signature, type, or interface, run findReferences (and incomingCalls for functions) so you know every call site that has to change.

## After you edit

- A PostToolUse hook runs `eslint` on each TS/JS file you edit and reports the findings back to you. It never modifies the file, so fix what it reports with your own edits. It fires only in projects that have an ESLint config.
- Run `tsc --noEmit -p tsconfig.json` for the real, whole-project type check. The pushed diagnostics only cover open or affected files and can lag behind, so trust `tsc` when they disagree.
- For each `tsc` error that's left, follow the types with goToDefinition and hover back to where the mismatch starts, fix it there, and run `tsc` again.
- If a pushed diagnostic doesn't show up in `tsc --noEmit`, it's stale. Ignore it.

## You're done when

`tsc --noEmit` comes back clean and `eslint` has nothing left to report on the changed files.

**Nothing checks this for you.** There is no gate at the end of the turn: if you skip the type-check, broken code ships and nobody is told. Run `tsc --noEmit` yourself before you say the work is done, and treat its output as the verdict.
