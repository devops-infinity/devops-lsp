# python-lsp

Python support for Claude Code, part of the `devops-lsp` marketplace.

It runs `basedpyright` for code intelligence and adds a notify-only layer: a `ruff check` after each edit reports the findings without changing the file, and a `basedpyright` gate script the bundled skill runs over the whole project. Nothing is ever fixed or formatted automatically.

Install the tools, then the plugin:

```sh
uv tool install basedpyright
uv tool install ruff
claude plugin marketplace add https://github.com/devops-infinity/devops-lsp
claude plugin install python-lsp@devops-lsp
```

The hooks also need `jq` and `git` on your PATH. It covers `.py` and `.pyi`.

The per-edit check only runs in projects that opted into ruff: a `ruff.toml`, a `.ruff.toml`, or a `[tool.ruff]` section in `pyproject.toml`. [The marketplace README](../../README.md) has the full dependency list, the reason basedpyright is the default, and how to turn the gate on.
