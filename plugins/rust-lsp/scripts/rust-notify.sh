#!/bin/sh
# PostToolUse hook: report a rustfmt parse failure on the edited .rs file; never modify it.
set -u

newline='
'

command -v jq >/dev/null 2>&1 || exit 0

script_dir="$(cd "$(dirname -- "$0")" && pwd)" || exit 0
# shellcheck disable=SC1091  # resolved beside this script; shellcheck cannot follow the dynamic path
. "$script_dir/toolchain-pin.sh"

report_context() {
	jq -n --arg context "$1" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $context}}'
}

hook_input="$(cat)"
file_path="$(printf '%s' "$hook_input" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)"

case "$file_path" in
*.rs) ;;
*) exit 0 ;;
esac
[ -f "$file_path" ] || exit 0

file_dir="$(cd "$(dirname -- "$file_path")" 2>/dev/null && pwd)" || exit 0

# an edition is read from the nearest manifest, and from an ancestor only when
# the nearest one inherits it with edition.workspace; cargo defaults to 2015
nearest_manifest=""
edition=""
inherits_edition=false
edition_walk_dir="$file_dir"
while [ -n "$edition_walk_dir" ] && [ "$edition_walk_dir" != "/" ]; do
	if [ -f "$edition_walk_dir/Cargo.toml" ]; then
		if [ -z "$nearest_manifest" ]; then
			nearest_manifest="$edition_walk_dir/Cargo.toml"
			edition="$(grep -m1 -E '^[[:space:]]*edition[[:space:]]*=[[:space:]]*"[0-9]{4}"' "$edition_walk_dir/Cargo.toml" 2>/dev/null |
				sed -E 's/.*"([0-9]{4})".*/\1/' || true)"
			grep -qE '^[[:space:]]*edition\.workspace' "$edition_walk_dir/Cargo.toml" 2>/dev/null && inherits_edition=true
			[ "$inherits_edition" = false ] && break
		elif [ -z "$edition" ]; then
			edition="$(grep -m1 -E '^[[:space:]]*edition[[:space:]]*=[[:space:]]*"[0-9]{4}"' "$edition_walk_dir/Cargo.toml" 2>/dev/null |
				sed -E 's/.*"([0-9]{4})".*/\1/' || true)"
			break
		else
			break
		fi
	fi
	edition_walk_dir="$(dirname -- "$edition_walk_dir")"
done
[ -n "$nearest_manifest" ] || exit 0
[ -n "$edition" ] || edition="2015"

pinned_toolchain_missing "$file_dir" && exit 0

(cd / && rustfmt --version >/dev/null 2>&1) || exit 0

# the --check diff is formatting drift and is dropped; only stderr (a parse failure) is reported
rustfmt_stderr="$(cd "$file_dir" && rustfmt --edition "$edition" --check --color never "$file_path" 2>&1 >/dev/null)"
[ -n "$rustfmt_stderr" ] || exit 0

report_context "devops-lsp: rustfmt cannot parse ${file_path}. Usually this means the file has a syntax error. Nothing is fixed automatically; fix it yourself:${newline}${rustfmt_stderr}"
exit 0
