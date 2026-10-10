---
name: rust-notify
description: Work on Rust with the language server and the project's own checks. Use when editing, refactoring, or reviewing .rs files, when cargo, clippy, borrow-checker, trait, or lifetime errors show up, or when asked to fix, check, or format a Rust crate or Cargo workspace.
---

# Rust notify

You have a Rust language server (rust-analyzer), and it's read-only. It can look things up (goToDefinition, goToImplementation, findReferences, hover, documentSymbol, workspaceSymbol, and call hierarchy). What it can't do is change code: no quick fixes, no rename, no organize-imports, no formatting. Nothing fixes or formats anything for you. The checks report the failures, and the fixing is yours.

Don't wait for the server to tell you something broke. Its compiler diagnostics come from `cargo`, and `cargo` only re-runs when the editor reports a file as saved, which Claude Code does not reliably do. A type error you introduce can sit there completely unreported until you run clippy yourself. Treat the absence of diagnostics as no information at all, and run the check yourself.

## Before you edit

- Hover a binding to read the type the compiler inferred. Rust elides most types, so the source text alone doesn't tell you what something is. This is the most useful thing the server gives you.
- Use goToDefinition or documentSymbol to read a type's real shape instead of guessing its fields or variants.
- Before you touch a public signature, a trait method, or an enum's variants, run findReferences (and incomingCalls for functions) so you know every call site that has to change.
- Before you change a trait, run goToImplementation. A trait change breaks every implementor, and those are usually spread across files that never mention the trait by name.

## After you edit

- A PostToolUse hook runs `rustfmt --check` on each `.rs` file you edit and reports an error only when the file does not parse. It never reformats. When the project expects canonical formatting, run `cargo fmt` yourself.
- Run `cargo clippy --workspace --all-targets` for the real check. It does the full type and borrow check _and_ the lints in one pass, so you don't need a separate `cargo check`. This is the one command that tells you the truth.
- Trust `cargo clippy` over anything the server pushed. The pushed set lags, goes stale after a rename, and may never refresh at all.
- For each error, follow the types back with hover and goToDefinition to where the mismatch actually starts, fix it there, and run clippy again.

## Fix the cause, not the symptom

- Don't add `.clone()` to silence the borrow checker. A clone that exists only to end an argument with the compiler is a bug you'll pay for later. Work out which binding needs to own the data and restructure so it does.
- Don't add `#[allow(...)]` to silence a clippy lint unless you can say in one sentence why the lint is wrong here. Silencing a lint to make a check pass is not fixing it.
- Don't reach for `unsafe`, `unwrap()`, or `expect()` to get past a type or lifetime problem. In library and service code an error belongs in the return type.

## You're done when

`cargo clippy --workspace --all-targets` reports no errors. Clean up the warnings too: they're what clippy is for.

**Nothing checks this for you.** There is no gate at the end of the turn, and the server's own diagnostics may never refresh after an edit. If you skip clippy, broken code ships silently. Run it yourself and treat its output as the verdict.
