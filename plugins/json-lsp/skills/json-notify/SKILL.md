---
name: json-notify
description: Work on JSON and JSONC files with the language server and the project's own checks. Use when editing, refactoring, or reviewing .json or .jsonc files, when the JSON language server reports a schema or syntax problem, or when asked to fix or check JSON.
---

# JSON notify

You have a JSON language server (vscode-json-language-server), and it is read-only. It validates syntax, checks a file against its JSON Schema, completes properties, and reports document symbols. It does not change code. Nothing fixes anything for you. The checks report the failures, and the fixing is yours.

## Before you edit

- Hover a property to read its description and its type from the schema rather than guessing.
- Check the file's schema first. A `$schema` key in the file, or a match in the server's schema list, decides which schema validates it. `package.json`, `tsconfig.json`, `jsconfig.json`, `composer.json`, and `.eslintrc.json` are associated already.
- Never add a `$schema` key just to get validation. It changes the file, and the program that reads the JSON may reject the unknown key. Add the association in the plugin's `.lsp.json` settings instead.

## After you edit

- A PostToolUse hook runs `prettier --check` on each `.json` and `.jsonc` file you edit and reports what it finds: a parse failure, or formatting drift. It never writes, so fix the file yourself, and format it yourself with the project's Prettier when the project expects it. Prettier reads `.editorconfig`, so indentation follows the repository.
- Validate against the schema when the file has one. The language server reports a schema violation as a diagnostic; a syntax error and a schema error are different problems and need different fixes.

## The details that bite

- JSON has no comments and no trailing commas. JSONC allows both, and the server treats `.jsonc` files accordingly. Never add a comment to a `.json` file to explain something; it breaks every strict parser.
- Keep the file's own key order unless the project sorts keys. Prettier reformats whitespace and does not reorder keys, so a hand-sorted file stays sorted.
- `package.json` gets its own Prettier parser, `json-stringify`, which keeps its keys as written. That is why it survives a format pass unchanged in structure.
- A duplicate key is valid JSON to a parser that keeps the last one and a bug to every reader. Fix it rather than relying on order.
- A trailing newline is part of the format. Leave one at the end of the file.

## You are done when

`prettier --check` passes on the files you touched, and the language server reports no syntax or schema diagnostic on them.

**Nothing checks this for you.** There is no gate at the end of the turn. Run `prettier --check` yourself and treat its output as the verdict.
