#!/usr/bin/env bash
set -uo pipefail

input="$(cat)"
active="$(printf '%s' "$input" | jq -r '.stop_hook_active // false' 2>/dev/null || echo false)"
[ "$active" = "true" ] && exit 0

root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

changed="$(cd "$root" && git status --porcelain 2>/dev/null |
	sed -E 's/^.{3}//; s/^.* -> //; s/^"(.*)"$/\1/' | grep -E '\.rs$' || true)"
[ -n "$changed" ] || exit 0

# Probe from / so the probe itself cannot resolve a pinned toolchain and trigger a download.
(cd / && cargo --version >/dev/null 2>&1) || exit 0
(cd / && cargo clippy --version >/dev/null 2>&1) || exit 0

# Reads the filesystem only - it never runs rustup or cargo. Every one of those
# resolves the active toolchain from the working directory, so inside a project pinned
# to an uninstalled toolchain any of them makes rustup download it on the spot:
# gigabytes, silently, inside a hook. That includes `rustup toolchain list`.
pin_blocked() {
	rustup_home="${RUSTUP_HOME:-$HOME/.rustup}"
	[ -d "$rustup_home/toolchains" ] || return 1
	probe="$1"
	while [ -n "$probe" ] && [ "$probe" != "/" ]; do
		for pin in rust-toolchain.toml rust-toolchain; do
			[ -f "$probe/$pin" ] || continue
			channel="$(grep -m1 -E '^[[:space:]]*channel[[:space:]]*=' "$probe/$pin" 2>/dev/null |
				sed -E 's/.*=[[:space:]]*"?([^"[:space:]]+)"?.*/\1/' || true)"
			# The legacy `rust-toolchain` file is a bare channel name, not TOML.
			if [ -z "$channel" ] && [ "$pin" = "rust-toolchain" ]; then
				channel="$(head -n1 "$probe/$pin" 2>/dev/null | tr -d '[:space:]')"
			fi
			[ -n "$channel" ] || return 1
			for tc in "$rustup_home/toolchains/$channel" "$rustup_home/toolchains/$channel"-*; do
				[ -d "$tc" ] && return 1
			done
			return 0
		done
		probe="$(dirname "$probe")"
	done
	return 1
}

# Every Cargo workspace touched by a changed file. A Cargo project does not have to
# sit at the git root, and one repo can hold several, so resolve them from the files.
workspaces="$(printf '%s\n' "$changed" | while IFS= read -r rel; do
	[ -n "$rel" ] || continue
	dir="$root/$(dirname "$rel")"
	[ -d "$dir" ] || continue
	pin_blocked "$dir" && continue
	manifest="$(cd "$dir" && cargo locate-project --workspace --message-format plain 2>/dev/null || true)"
	if [ -z "$manifest" ]; then
		probe="$(cd "$dir" && pwd)"
		while [ -n "$probe" ] && [ "$probe" != "/" ]; do
			if [ -f "$probe/Cargo.toml" ]; then
				manifest="$probe/Cargo.toml"
				break
			fi
			probe="$(dirname "$probe")"
		done
	fi
	[ -n "$manifest" ] && dirname "$manifest"
done | sort -u)"
[ -n "$workspaces" ] || exit 0

errors=""
warncount=0
while IFS= read -r ws; do
	[ -n "$ws" ] || continue
	out="$(cd "$ws" && cargo clippy --workspace --all-targets --color=never --message-format=json 2>/dev/null || true)"
	[ -n "$out" ] || continue
	found="$(printf '%s' "$out" | jq -r --arg ws "$ws" '
    select(.reason == "compiler-message")
    | .message
    | select(.level == "error")
    | . as $m
    | (([.spans[]? | select(.is_primary)] | first) // null) as $s
    | if $s then "\($ws)/\($s.file_name):\($s.line_start):\($s.column_start): \($m.message)" else $m.message end
  ' 2>/dev/null | grep -v '^aborting due to' || true)"
	[ -n "$found" ] && errors="$errors$found"$'\n'
	n="$(printf '%s' "$out" | jq -r '
    select(.reason == "compiler-message") | .message | select(.level == "warning") | .message
  ' 2>/dev/null | sort -u | grep -c . || true)"
	warncount=$((warncount + ${n:-0}))
done <<EOF
$workspaces
EOF

errors="$(printf '%s' "$errors" | grep -v '^$' | awk '!seen[$0]++' || true)"
[ -n "$errors" ] || exit 0

total="$(printf '%s\n' "$errors" | wc -l | tr -d ' ')"
shown="$(printf '%s\n' "$errors" | head -40)"
[ "$total" -gt 40 ] && shown="$shown"$'\n'"... $((total - 40)) more"

reason="devops-lsp Rust gate: 'cargo clippy --workspace --all-targets' reported ${total} error(s). Fix them before finishing:"$'\n'"$shown"
[ "$warncount" -gt 0 ] && reason="$reason"$'\n\n'"There are also ${warncount} clippy warning(s)."

jq -n --arg r "$reason" '{decision: "block", reason: $r}'
exit 0
