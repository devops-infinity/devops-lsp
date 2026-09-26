# shell-lsp

Shell script support for Claude Code, part of the `devops-lsp` marketplace.

It runs `bash-language-server` for code intelligence and adds an auto-heal layer: `shellcheck --format=diff` fixes and then `shfmt` after edits, plus a `shellcheck` gate script the bundled skill runs over the changed files.

Install the tools, then the plugin:

```sh
bun add -g bash-language-server@5.8.1
brew install shellcheck shfmt
claude plugin marketplace add https://github.com/devops-infinity/devops-lsp
claude plugin install shell-lsp@devops-lsp
```

The hooks also need `jq` and `git` on your PATH. It covers `.sh`, `.bash`, and `.bats`.

`.zsh` is deliberately not mapped: shellcheck cannot parse zsh, so pointing it at zsh files produces noise rather than findings. [The marketplace README](../../README.md) has the full dependency list and how to turn the gate on.
