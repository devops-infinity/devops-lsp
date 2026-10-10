---
name: yaml-notify
description: Work on YAML files with the language server and the project's own checks. Use when editing, refactoring, or reviewing .yaml or .yml files, when the YAML language server reports a schema or syntax problem, or when asked to fix or check a YAML file, a Kubernetes manifest, a CI workflow, or a Docker Compose file.
---

# YAML notify

You have a YAML language server (yaml-language-server), and it is read-only. It validates syntax, validates a file against its JSON Schema, completes properties, and reports document symbols. It does not change code. Nothing fixes anything for you. The checks report the failures, and the fixing is yours.

## Before you edit

- Hover a key to read its description and type from the schema rather than guessing.
- Check the file's schema first. SchemaStore associates the common ones by filename, so a `.github/workflows/` file validates as a GitHub workflow and a `docker-compose.yml` validates as Compose. The server checks the modeline, then a `$schema` key, then the configured associations, then SchemaStore.
- Set `yaml.schemas` in the plugin's `.lsp.json` when a project file has no schema and no filename SchemaStore knows. Do not add a `$schema` key to the file to get validation; it changes the document.
- A modeline at the top of the file is the per-file override, and it is the one association that wins over everything else: `# yaml-language-server: $schema=<url>`.

## After you edit

- A PostToolUse hook runs `prettier --check` on each `.yaml` and `.yml` file you edit and reports what it finds: a parse failure, or formatting drift. It never writes, so fix the file yourself, and format it yourself with the project's Prettier when the project expects it. Prettier reads `.editorconfig`, so indentation follows the repository.
- Run `yamllint <files>` for the real check. It catches a duplicate key, a bad indentation, a trailing space, and a truthy value that will change type.
- Prettier and yamllint disagree by default. Prettier writes one space before an inline comment, pads a flow mapping as `{ a: 1 }`, and never adds a `---` start; yamllint's stock rules want the opposite on all three and would flag every file Prettier writes. The check script therefore passes yamllint a Prettier-compatible default, and uses the project's own `.yamllint` when it has one.

## The details that bite

- Indentation is two spaces, and a tab is never allowed. A tab is a parse error, not a style problem.
- Quote a value that could be read as another type. The bare word `no` parses as the boolean false, which is why a country code `NO` turns into `false` and why `on:` in a workflow is a boolean to YAML 1.1. Write `"NO"` and `"on"`.
- Keep the extension consistent with the repository. `.yaml` is the extension the YAML project recommends and the one RFC 9512 lists first, while `.yml` is common and fully supported. Both map here. Never keep a `config.yaml` and a `config.yml` side by side; a tool that reads one will miss the other.
- An anchor and an alias are part of the format, not noise. Prettier preserves them, so leave them in place.
- A duplicate key is silently last-one-wins. Fix it rather than relying on order.
- A `---` document start is optional, and a file with several documents needs one between them.
- Never disable a yamllint rule inline without saying in one sentence why the tool is wrong here.

## You are done when

`yamllint` reports no errors and `prettier --check` passes on the files you touched, and the language server reports no syntax or schema diagnostic on them.

**Nothing checks this for you.** There is no gate at the end of the turn. Run `yamllint` and `prettier --check` yourself and treat their output as the verdict.
