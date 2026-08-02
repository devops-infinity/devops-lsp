# php-lsp

PHP support for Claude Code, part of the `devops-lsp` marketplace. It runs `intelephense` for code intelligence and adds an auto-heal layer: `php -l` plus the project's own formatter after edits, and a PHPStan gate that holds a turn open until the project analyses clean.

Install the tools, then the plugin:

```sh
bun add -g intelephense@1.18.5
composer global require laravel/pint phpstan/phpstan
claude plugin install php-lsp@devops-lsp
```

The hooks also need `jq`, `git`, and `php` on your PATH. It covers `.php`, `.phtml`, and the legacy numbered extensions.

Intelephense's diagnostics are turned **off** on purpose — it has no framework awareness and reports false "undefined method" errors on Eloquent, facades, and Filament. PHPStan owns diagnostics instead. Blade templates are not mapped, and `.inc` is not claimed. The marketplace README has the licensing details, the formatter detection order, and how to turn the gate off.
