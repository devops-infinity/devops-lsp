#!/usr/bin/env bash
set -uo pipefail

input="$(cat)"
file="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)"

case "$file" in
  *.ts | *.tsx | *.mts | *.cts | *.js | *.jsx | *.mjs | *.cjs) ;;
  *) exit 0 ;;
esac
[ -f "$file" ] || exit 0

dir="$(dirname "$file")"
root="$(cd "$dir" 2>/dev/null && { git rev-parse --show-toplevel 2>/dev/null || pwd; })"
[ -n "${root:-}" ] || exit 0

eslint_config=""
for c in eslint.config.js eslint.config.mjs eslint.config.cjs eslint.config.ts .eslintrc .eslintrc.js .eslintrc.cjs .eslintrc.json .eslintrc.yml .eslintrc.yaml; do
  if [ -f "$root/$c" ]; then
    eslint_config="1"
    break
  fi
done
[ -n "$eslint_config" ] || exit 0

out="$(cd "$root" && npx --no-install eslint --fix "$file" 2>&1 || true)"
[ -n "$out" ] || exit 0

ctx="devops-lsp auto-heal ran 'eslint --fix' on ${file}. Unresolved lint output below; address it:"$'\n'"$out"
jq -n --arg c "$ctx" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $c}}'
exit 0
