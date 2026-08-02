# python-lsp

Python support for Claude Code, part of the `devops-lsp` marketplace. It runs `basedpyright` for code intelligence and adds an auto-heal layer: `ruff check --fix` and `ruff format` after edits, and a `basedpyright` gate that holds a turn open until the project type-checks.

Install the tools, then the plugin:

```sh
uv tool install basedpyright
uv tool install ruff
claude plugin install python-lsp@devops-lsp
```

The hooks also need `jq` and `git` on your PATH. It covers `.py` and `.pyi`.

The formatter only runs in projects that opted into ruff — a `ruff.toml`, a `.ruff.toml`, or a `[tool.ruff]` section in `pyproject.toml`. The marketplace README has the full dependency list, the reason for basedpyright over stock pyright, and how to turn the gate off.
