# php-lsp

PHP support for Claude Code, part of the `devops-lsp` marketplace.

It runs `intelephense` for code intelligence and adds an auto-heal layer: `php -l` plus a formatter after edits, and a PHPStan gate script the bundled skill runs over every touched project.

Install the tools, then the plugin:

```sh
bun add -g intelephense@1.18.5
composer global require laravel/pint phpstan/phpstan
claude plugin marketplace add https://github.com/devops-infinity/devops-lsp
claude plugin install php-lsp@devops-lsp
```

The hooks also need `jq`, `git`, and `php` on your PATH. It covers `.php`, `.phtml`, `.php3`, `.php4`, `.php5`, `.php7`, `.php8`, and `.phps`.

Intelephense's diagnostics are turned **off** on purpose: it has no framework awareness and reports false "undefined method" errors on Eloquent, facades, and Filament. PHPStan owns diagnostics instead. Blade templates are not mapped, and `.inc` is not claimed. [The marketplace README](../../README.md) has the licensing details, the formatter detection order, and how to turn the gate on.
