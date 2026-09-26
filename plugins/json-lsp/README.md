# json-lsp

JSON and JSONC support for Claude Code, part of the `devops-lsp` marketplace.

It runs the VS Code JSON language server for code intelligence and adds an auto-heal layer: `prettier --write` after edits, and a `prettier --check` gate script the bundled skill runs over the changed files.

Install the tools, then the plugin:

```sh
bun add -g vscode-langservers-extracted@4.10.0 prettier@3.9.9
claude plugin marketplace add https://github.com/devops-infinity/devops-lsp
claude plugin install json-lsp@devops-lsp
```

The hooks also need `jq` and `git` on your PATH. It covers `.json` and `.jsonc`.

The server validates a file against its JSON Schema. `package.json`, `tsconfig.json`, `jsconfig.json`, `composer.json`, and `.eslintrc.json` are associated by filename already; add more in `plugins/json-lsp/.lsp.json` under `settings.json.schemas`. [The marketplace README](../../README.md) has the full dependency list, the schema notes, and how to turn the gate on.
