---
name: python-autoheal
description: Auto-heal Python after edits. Use when editing, refactoring, or reviewing .py or .pyi files, when type errors, import errors, or lint failures show up, or when asked to fix, clean up, format, or type-check Python.
---

# Python auto-heal

You have a Python language server (basedpyright), and it's read-only. It can look things up — goToDefinition, goToImplementation, findReferences, hover, documentSymbol, workspaceSymbol, and call hierarchy — and it reports type errors for the files you have open. What it can't do is change code: no quick fixes, no rename, no organize-imports, no formatting. You do the fixing with the command-line tools below.

The server is set to `openFilesOnly`, so it says nothing about files you haven't touched. A change that breaks a caller three modules away will not show up until you check the project. Run the check yourself rather than waiting to be told.

## Before you edit

- Hover a name to see the type that was actually inferred. Python's annotations are optional and often absent or wrong, so the inferred type is the real one.
- Use goToDefinition to read a class or function instead of guessing its shape from how it's called.
- Before you change a function signature, a class attribute, or anything exported from a module, run findReferences. Python resolves names at runtime, so the compiler will not catch a caller you forgot.

## After you edit, fix it — don't just report it

- Lint and formatting are already handled. A PostToolUse hook runs `ruff check --fix` and then `ruff format` on each file you edit, and hands back whatever ruff could not fix. It only fires in projects that opted into ruff.
- Run `basedpyright` for the real check. It covers the whole project, not just open files, and it is what the Stop gate runs.
- For each error, follow the types back with hover and goToDefinition to where the mismatch starts, fix it there, and run the check again.

## Fix the cause, not the symptom

- Don't add `# type: ignore` to make an error go away unless you can say in one sentence why the checker is wrong. Silencing a real error moves the failure to runtime.
- Don't widen a type to `Any` to end an argument with the checker. `Any` disables checking for everything downstream that touches the value.
- Don't wrap a call in `try/except` to hide an error the checker found. If the error is real, handle the specific exception; if it isn't, fix the type.
- Don't add a `cast()` where a real narrowing check (`isinstance`, an early return, or an assert) would do the job honestly.

## You're done when

`basedpyright` reports no errors and `ruff check` is clean on the files you touched. A Stop hook runs the project type-check before the turn can end, so this isn't optional.
