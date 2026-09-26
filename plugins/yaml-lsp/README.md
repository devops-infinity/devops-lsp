# yaml-lsp

YAML support for Claude Code, part of the `devops-lsp` marketplace.

It runs the Red Hat YAML language server for code intelligence and adds an auto-heal layer: `prettier --write` after edits, and a `yamllint` plus `prettier --check` gate script the bundled skill runs over the changed files.

Install the tools, then the plugin:

```sh
bun add -g yaml-language-server@1.24.0 prettier@3.9.9
uv tool install yamllint
claude plugin marketplace add https://github.com/devops-infinity/devops-lsp
claude plugin install yaml-lsp@devops-lsp
```

The hooks also need `jq` and `git` on your PATH. It covers `.yaml` and `.yml`, both of which map to the same language.

The server validates a file against its JSON Schema and pulls schemas from the SchemaStore catalog by filename, so a GitHub workflow, a Compose file, and a Kubernetes manifest validate with no setup. Set `yaml.schemas` in `plugins/yaml-lsp/.lsp.json` for a file SchemaStore does not know. [The marketplace README](../../README.md) has the full dependency list, the `.yaml` and `.yml` note, and how to turn the gate on.
