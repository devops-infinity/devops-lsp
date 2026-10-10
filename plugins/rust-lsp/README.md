# rust-lsp

Rust support for Claude Code, part of the `devops-lsp` marketplace.

It runs `rust-analyzer` for code intelligence and adds a notify-only layer: a `rustfmt` parse check after each edit reports a syntax error without changing the file, and a `cargo clippy` gate script the bundled skill runs over the whole workspace. Nothing is ever fixed or formatted automatically.

Install the tools, then the plugin:

```sh
rustup component add rust-analyzer rust-src clippy rustfmt
claude plugin marketplace add https://github.com/devops-infinity/devops-lsp
claude plugin install rust-lsp@devops-lsp
```

The hooks also need `jq` and `git` on your PATH. It covers `.rs` files and applies to every Cargo project you open.

[The marketplace README](../../README.md) has the full dependency list, the choice between the rustup and standalone builds of rust-analyzer, the performance notes, and how to turn the gate on.
