# shell-lsp

Shell script support for Claude Code, part of the `devops-lsp` marketplace.

It runs `bash-language-server` for code intelligence and adds a notify-only layer: a `shellcheck` check after each edit reports the findings without changing the file, and a `shellcheck` gate script the bundled skill runs over the changed files. Nothing is ever fixed or formatted automatically.

Install the tools, then the plugin:

```sh
bun add -g bash-language-server@5.8.1
brew install shellcheck
claude plugin marketplace add https://github.com/devops-infinity/devops-lsp
claude plugin install shell-lsp@devops-lsp
```

The hooks also need `jq` and `git` on your PATH. It covers `.sh`, `.bash`, and `.bats`.

`.zsh` is deliberately not mapped: shellcheck cannot parse zsh, so pointing it at zsh files produces noise rather than findings. [The marketplace README](../../README.md) has the full dependency list and how to turn the gate on.
