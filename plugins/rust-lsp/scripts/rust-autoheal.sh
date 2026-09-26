#!/bin/sh
set -u

nl='
'

command -v jq >/dev/null 2>&1 || exit 0

input="$(cat)"
file="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)"

case "$file" in
*.rs) ;;
*) exit 0 ;;
esac
[ -f "$file" ] || exit 0

dir="$(cd "$(dirname -- "$file")" 2>/dev/null && pwd)" || exit 0

# reads the filesystem only: calling rustup here would download a pinned toolchain
pin_blocked() {
	rustup_home="${RUSTUP_HOME:-$HOME/.rustup}"
	[ -d "$rustup_home/toolchains" ] || return 1
	probe="$1"
	while [ -n "$probe" ] && [ "$probe" != "/" ]; do
		for pin in rust-toolchain.toml rust-toolchain; do
			[ -f "$probe/$pin" ] || continue
			channel="$(grep -m1 -E '^[[:space:]]*channel[[:space:]]*=' "$probe/$pin" 2>/dev/null |
				sed -E 's/.*=[[:space:]]*"?([^"[:space:]]+)"?.*/\1/' || true)"
			if [ -z "$channel" ] && [ "$pin" = "rust-toolchain" ]; then
				channel="$(head -n1 "$probe/$pin" 2>/dev/null | tr -d '[:space:]')"
			fi
			[ -n "$channel" ] || return 1
			for tc in "$rustup_home/toolchains/$channel" "$rustup_home/toolchains/$channel"-*; do
				[ -d "$tc" ] && return 1
			done
			return 0
		done
		probe="$(dirname -- "$probe")"
	done
	return 1
}

manifest=""
edition=""
probe="$dir"
while [ -n "$probe" ] && [ "$probe" != "/" ]; do
	if [ -f "$probe/Cargo.toml" ]; then
		[ -n "$manifest" ] || manifest="$probe/Cargo.toml"
		if [ -z "$edition" ]; then
			edition="$(grep -m1 -E '^[[:space:]]*edition[[:space:]]*=[[:space:]]*"[0-9]{4}"' "$probe/Cargo.toml" 2>/dev/null |
				sed -E 's/.*"([0-9]{4})".*/\1/' || true)"
		fi
	fi
	probe="$(dirname -- "$probe")"
done
[ -n "$manifest" ] || exit 0
[ -n "$edition" ] || edition="2015"

pin_blocked "$dir" && exit 0

(cd / && rustfmt --version >/dev/null 2>&1) || exit 0

out="$(cd "$dir" && rustfmt --edition "$edition" --color never "$file" 2>&1)"
rc=$?
[ "$rc" -ne 0 ] || exit 0
[ -n "$out" ] || exit 0

ctx="devops-lsp auto-heal ran 'rustfmt --edition ${edition}' on ${file} and it did not format cleanly. Usually this means the file does not parse. Fix it:${nl}${out}"
jq -n --arg c "$ctx" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $c}}'
exit 0
