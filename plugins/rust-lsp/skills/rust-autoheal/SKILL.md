---
name: rust-autoheal
description: Auto-heal Rust after edits. Use when editing, refactoring, or reviewing .rs files, when cargo, clippy, borrow-checker, trait, or lifetime errors show up, or when asked to fix, clean up, format, or check a Rust crate or Cargo workspace.
---

# Rust auto-heal

You have a Rust language server (rust-analyzer), and it's read-only. It can look things up — goToDefinition, goToImplementation, findReferences, hover, documentSymbol, workspaceSymbol, and call hierarchy. What it can't do is change code: no quick fixes, no rename, no organize-imports, no formatting. You do the fixing with the command-line tools below.

Don't wait for the server to tell you something broke. Its compiler diagnostics come from `cargo`, and `cargo` only re-runs when the editor reports a file as saved — which this harness does not reliably do. A type error you introduce can sit there completely unreported until the Stop gate catches it. Treat the absence of diagnostics as no information at all, and run the check yourself.

## Before you edit

- Hover a binding to read the type the compiler inferred. Rust elides most types, so the source text alone doesn't tell you what something is — this is the single most useful thing the server gives you.
- Use goToDefinition or documentSymbol to read a type's real shape instead of guessing its fields or variants.
- Before you touch a public signature, a trait method, or an enum's variants, run findReferences (and incomingCalls for functions) so you know every call site that has to change.
- Before you change a trait, run goToImplementation. A trait change breaks every implementor, and those are usually spread across files that never mention the trait by name.

## After you edit, fix it — don't just report it

Work through the changed crates and repeat until they're clean:

- Formatting is already handled. A PostToolUse hook runs `rustfmt` on each file you edit, with the crate's own edition. If it hands back an error, the file doesn't parse — fix that first, because nothing else will work until it does.
- Run `cargo clippy --workspace --all-targets` for the real check. It does the full type and borrow check _and_ the lints in one pass, so you don't need a separate `cargo check`. This is the one command that tells you the truth.
- Trust `cargo clippy` over anything the server pushed. The pushed set lags, goes stale after a rename, and may never refresh at all.
- For each error, follow the types back with hover and goToDefinition to where the mismatch actually starts, fix it there, and run clippy again.

## Fix the cause, not the symptom

- Don't add `.clone()` to silence the borrow checker. A clone that exists only to end an argument with the compiler is a bug you'll pay for later. Work out which binding needs to own the data and restructure so it does.
- Don't add `#[allow(...)]` to silence a clippy lint unless you can say in one sentence why the lint is wrong here. Silencing a lint to make a gate pass is not fixing it.
- Don't reach for `unsafe`, `unwrap()`, or `expect()` to get past a type or lifetime problem. In library and service code an error belongs in the return type.

## About `cargo clippy --fix`

Use it deliberately, not as a routine step, and know its three limits: it can't target a single file (`--fix` implies the whole target set), it refuses to run on a dirty working tree unless you pass `--allow-dirty`, and it exits 0 whether or not it changed anything — so its exit code tells you nothing. Always re-run plain `cargo clippy` afterward to see what's actually left.

## You're done when

`cargo clippy --workspace --all-targets` reports no errors. A Stop hook runs it before the turn can end, so this isn't optional. Clean up the warnings it reports too — they're what clippy is for.
