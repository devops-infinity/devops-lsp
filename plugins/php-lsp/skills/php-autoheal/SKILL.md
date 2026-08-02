---
name: php-autoheal
description: Auto-heal PHP after edits. Use when editing, refactoring, or reviewing .php or .phtml files, when PHPStan or Intelephense reports problems, or when asked to fix, clean up, format, or type-check PHP or a Laravel project.
---

# PHP auto-heal

You have a PHP language server (Intelephense), and it is read-only. It resolves definitions, references, hovers, document and workspace symbols, and implementations. It does not provide call hierarchy on the free tier, and it cannot change code. You do the fixing with the command-line tools below.

**The server does not report diagnostics.** That is deliberate, not a fault. Intelephense has no framework awareness, so on Eloquent magic methods, facades, and Filament's fluent builders it reports "undefined method" on code that is perfectly correct. Those false positives cost more than the findings are worth. PHPStan owns diagnostics instead, and it runs at the Stop gate. So do not wait to be told something is wrong — run the check yourself.

## Before you edit

- Use goToDefinition to read a class before calling it. PHP's dynamic features mean the shape you assume from a call site is often not the real one.
- Before you change a public method signature, a constructor, or anything in an interface, run findReferences. PHP resolves most of this at runtime, so nothing will catch a missed caller before production.
- Use goToImplementation on an interface before you change it.

## After you edit, fix it — don't just report it

- Syntax and formatting are already handled. A PostToolUse hook runs `php -l` first, and if the file does not parse it stops there and tells you. If it parses, the project's own formatter runs — Pint, PHP-CS-Fixer, or phpcbf, whichever the project actually configured.
- Run `vendor/bin/phpstan analyse` for the real check. If the project has no `phpstan.neon`, pass `--level=5` explicitly. **Never run PHPStan with no config and no level** — it silently defaults to level 0, which passes almost anything and tells you nothing.
- For each error, follow the types back with goToDefinition to where the mismatch starts, fix it there, and run the check again.

## Fix the cause, not the symptom

- Don't add `@phpstan-ignore-next-line` or `@phpstan-ignore` to make an error disappear unless you can say in one sentence why the analyzer is wrong. If it is a framework limitation, that is a reason; "it was noisy" is not.
- Don't widen a parameter or return type to `mixed` to end an argument with the analyzer. `mixed` disables checking for everything downstream that touches the value.
- Don't add a `@param` or `@return` annotation that contradicts the real behavior. A wrong annotation is worse than none — it makes the analyzer confidently wrong.
- Don't reach for `@` error suppression. Handle the failure or let it throw.
- In Laravel, prefer a real type over a docblock where the framework allows it, and remember that Larastan resolves much of the Eloquent magic that plain PHPStan cannot.

## You're done when

`vendor/bin/phpstan analyse` reports no errors and the file parses.

**Nothing checks this for you.** There is no gate at the end of the turn, and the language server's diagnostics are switched off on purpose. PHPStan is the only thing that will tell you the code is wrong, and only if you run it. Remember to pass an explicit `--level` when the project has no `phpstan.neon`, or it analyses at level 0 and reports almost nothing.
