# typescript-lsp

TypeScript and JavaScript support for Claude Code, part of the `devops-lsp` marketplace. It runs `typescript-language-server` for code intelligence and adds an auto-heal layer: `eslint --fix` after edits, and a `tsc --noEmit` gate that holds a turn open until the project type-checks.

Install the tools, then the plugin:

```sh
bun add -g typescript-language-server@5.3.0 typescript@6.0.3
claude plugin install typescript-lsp@devops-lsp
```

The hooks also need `jq` and `npx` on your PATH, and each project needs its own `eslint` and `tsconfig.json` for the checks to run. The marketplace README has the full dependency list, the Next.js setup, the performance notes, and how to turn the type-check gate off.

It covers `.ts`, `.tsx`, `.mts`, `.cts`, `.js`, `.jsx`, `.mjs`, and `.cjs`, and applies to every TS/JS project you open.
