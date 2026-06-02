# devops-lsp

A small marketplace of Claude Code language-server plugins, kept under the DevOps brand. Add it once and Claude Code gets real TypeScript and JavaScript intelligence — plus an auto-heal layer — in every repo you open, whether that's a NestJS API, a Next.js app, or any other TS/JS project.

The first plugin is `typescript-lsp`. It does two things:

- Wires up `typescript-language-server` so Claude resolves definitions, references, hovers, symbols, and call hierarchy from the type system instead of guessing from text.
- Adds an auto-heal layer. After Claude edits a TS/JS file, a hook runs `eslint --fix` on it; before a turn can end, another hook runs a full `tsc --noEmit` and won't let Claude stop while type errors remain. A bundled skill teaches Claude how to use all of this together.

## What you need installed

This plugin tells Claude Code how to reach a language server and which checks to run. It doesn't ship those tools, so they need to be on your PATH. Here is the full list and how to get each one.

For the language server:

- `typescript-language-server` and `typescript`. Install them globally with Bun:
  ```sh
  bun add -g typescript-language-server@5.3.0 typescript@6.0.3
  ```
  Versions are pinned to the latest stable as of June 3rd 2026; bump them when newer releases ship.

For the auto-heal hooks:

- `jq` — the hooks read Claude's JSON from stdin with it. macOS: `brew install jq`. Debian or Ubuntu: `sudo apt-get install jq`.
- `node` and `npx` — the hooks call each project's local `eslint` and `tsc` through `npx --no-install`. Any recent Node works.
- `git` — the type-check gate only runs when you have uncommitted TS changes, which it checks with `git status`. Outside a git repo, the gate skips quietly.

Per project, not global:

- `eslint` with a config, and `typescript` with a `tsconfig.json`, as dev dependencies. The hooks use each project's own copies and skip cleanly when a project doesn't have them. Most TS projects already do.

If a tool from the first two groups is missing, install it before you rely on the plugin. The server won't attach without `typescript-language-server`, and the hooks no-op (rather than crash) when `jq`, `npx`, or `git` aren't there.

## Install

Register the marketplace, then install the plugin:

```sh
claude plugin marketplace add https://github.com/devops-infinity/devops-lsp
claude plugin install typescript-lsp@devops-lsp
```

Restart Claude Code so the language server attaches, then confirm it loaded:

```sh
claude plugin details typescript-lsp@devops-lsp
claude --debug   # look for: Total LSP servers loaded: 1
```

If the LSP tool doesn't appear, set `ENABLE_LSP_TOOL=1` in your environment or `settings.json` and restart. Some Claude Code builds still need that flag even though it's meant to be on by default.

## What Claude gets from it

Claude Code's LSP tool exposes nine read-only operations, and this plugin makes all of them work for TS/JS: go to definition, go to implementation, find references, hover, document symbols, workspace symbols, and call hierarchy (prepare, incoming, outgoing). The server also pushes type and lint errors into Claude's context right after each edit, so Claude sees mistakes without being asked.

Worth being clear about one limit: the LSP can read your code, but it can't change it. Claude Code doesn't expose quick-fix, rename, or format through the language server. That's why the fixing runs through command-line tools instead.

## The auto-heal layer

Three pieces work together.

- A skill, `ts-autoheal`, tells Claude how to work on TS/JS: check references before changing a shared signature, run `eslint --fix` and `tsc --noEmit` after editing, trust `tsc` over the pushed diagnostics when they disagree, and keep going until both are clean.
- A `PostToolUse` hook runs `eslint --fix` on each TS/JS file Claude writes or edits, then hands any leftover lint back to Claude. It only fires in projects that have an ESLint config, and it's quick because it runs on the single file.
- A `Stop` hook runs a full `tsc --noEmit` before Claude is allowed to finish. If the project doesn't type-check, Claude is sent back to fix it. To stay out of the way, this gate only runs inside a git repo that has a `tsconfig.json` and uncommitted TS changes.

A note on speed, since this is a global plugin. A whole-project `tsc --noEmit` can take anywhere from a second to a minute on a large codebase, and the `Stop` gate runs it at the end of any turn where you have uncommitted TS changes. If that's too heavy for a given machine or repo, delete the `Stop` block from `plugins/typescript-lsp/hooks/hooks.json`, or remove the hook entirely. You keep the fast per-edit `eslint --fix` and the skill guidance, and per-edit type feedback still arrives for free through the server's pushed diagnostics.

## NestJS and Next.js

NestJS and plain TS/JS projects work as-is. The server reads each project's `tsconfig.json`.

Next.js needs one extra step to get its own diagnostics — the App Router route checks, the `'use client'` rules, and typed routes. List the Next plugin in the project's `tsconfig.json` under `"plugins": [{ "name": "next" }]`, keep `.next/types/**/*.ts` in the `include` array, and run `next dev`, `next build`, or `next typegen` once so the generated types exist. The server uses the workspace TypeScript, so the Next plugin loads with it.

## Tuning a large repo

The server's memory ceiling lives in `plugins/typescript-lsp/.lsp.json` as `maxTsServerMemory`, in megabytes. It's a ceiling, not a reservation, so the default of 8192 is safe on small projects and gives a large monorepo headroom before it runs out of memory. Lower it if you're tight on RAM.

To quiet stale or noisy diagnostics, add the TypeScript error codes you want to mute to `settings.diagnostics.ignoredCodes` in the same file.

## Adding more language servers

The marketplace is built to hold more than one. To add a Python or Rust server, for example:

1. Create `plugins/<name>/.claude-plugin/plugin.json` with the metadata and an `lspServers` pointer.
2. Add `plugins/<name>/.lsp.json` with the server's command and extension mapping.
3. Add an entry to `.claude-plugin/marketplace.json` with `source` pointing at the new folder.
4. List the server's install command in this file so the next person knows what to install.

## License

MIT, copyright DevOps. Change it in `LICENSE` and the manifests if you'd prefer something else.
