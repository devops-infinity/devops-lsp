# typescript-lsp

TypeScript and JavaScript support for Claude Code, part of the `devops-lsp` marketplace.

It runs `typescript-language-server` for code intelligence and adds an auto-heal layer: `eslint --fix` after edits, and a `tsc --noEmit` gate script the bundled skill runs over the whole project.

Install the tools, then the plugin:

```sh
bun add -g typescript-language-server@6.0.1 typescript@6.0.3
claude plugin marketplace add https://github.com/devops-infinity/devops-lsp
claude plugin install typescript-lsp@devops-lsp
```

The hooks also need `jq`, `npx`, and `git` on your PATH, and each project needs its own `eslint` config and `tsconfig.json` for the checks to run. [The marketplace README](../../README.md) has the full dependency list, the Next.js setup, the performance notes, and how to turn the type-check gate on.

It covers `.ts`, `.tsx`, `.mts`, `.cts`, `.js`, `.jsx`, `.mjs`, and `.cjs`, and applies to every TS/JS project you open.
