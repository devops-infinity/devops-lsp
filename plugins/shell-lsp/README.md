# shell-lsp

Shell script support for Claude Code, part of the `devops-lsp` marketplace. It runs `bash-language-server` for code intelligence and adds an auto-heal layer: `shfmt` after edits, and a `shellcheck` gate that holds a turn open until no errors remain.

Install the tools, then the plugin:

```sh
bun add -g bash-language-server@5.6.0
brew install shellcheck shfmt
claude plugin install shell-lsp@devops-lsp
```

The hooks also need `jq` and `git` on your PATH. It covers `.sh`, `.bash`, and `.bats`.

`.zsh` is deliberately not mapped — shellcheck cannot parse zsh, so pointing it at zsh files produces noise rather than findings. The marketplace README has the full dependency list and how to turn the gate off.
