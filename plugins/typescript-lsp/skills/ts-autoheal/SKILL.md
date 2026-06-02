---
name: ts-autoheal
description: Auto-heal TypeScript and JavaScript after edits. Use when editing, refactoring, or reviewing .ts/.tsx/.js/.jsx/.mts/.cts files, when type or lint errors appear, or when asked to fix, clean up, or type-check TS/JS.
---

# TypeScript / JavaScript auto-heal workflow

A TypeScript/JavaScript language server is available. It is READ-ONLY: it provides goToDefinition, goToImplementation, findReferences, hover, documentSymbol, workspaceSymbol, and call hierarchy, plus type and lint diagnostics that are pushed into context automatically after each edit. The language server CANNOT apply quick fixes, rename symbols, organize imports, or format. Every remediation is done with the command-line tools below.

## Before editing

- Resolve a symbol with goToDefinition or documentSymbol instead of guessing its shape.
- Before changing any exported signature, type, or interface, run findReferences (and incomingCalls for functions) to enumerate every call site that must change.

## After editing — remediate, do not just report

Work on the changed files and repeat until clean:

- Run `eslint --fix` on the changed files to auto-fix lint issues and, where an import-order rule is configured, organize imports. A PostToolUse hook already attempts this automatically and reports what it could not fix.
- Run `tsc --noEmit -p tsconfig.json` for the authoritative, whole-project type check. Pushed diagnostics cover only opened or affected files and can be stale, so treat `tsc` as the source of truth.
- For each remaining `tsc` error, use goToDefinition and hover on the involved types to trace the mismatch to its origin, fix it there, and re-run `tsc`.
- Ignore pushed diagnostics that `tsc --noEmit` does not reproduce; they are stale.

## Done criteria

`tsc --noEmit` exits cleanly and `eslint` reports no remaining errors on the changed files. A Stop hook enforces the project type-check before the turn can end.
