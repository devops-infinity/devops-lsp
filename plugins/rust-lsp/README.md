# rust-lsp

Rust support for Claude Code, part of the `devops-lsp` marketplace. It runs `rust-analyzer` for code intelligence and adds an auto-heal layer: `rustfmt` after edits, and a `cargo clippy` gate that holds a turn open until the workspace has no errors.

Install the tools, then the plugin:

```sh
rustup component add rust-analyzer rust-src clippy rustfmt
claude plugin install rust-lsp@devops-lsp
```

The hooks also need `jq` and `git` on your PATH. It covers `.rs` files and applies to every Cargo project you open.

The marketplace README has the full dependency list, the choice between the rustup and standalone builds of rust-analyzer, the performance notes, and how to turn the gate off.
