#!/bin/sh
set -u

nl='
'

command -v jq >/dev/null 2>&1 || exit 0
command -v git >/dev/null 2>&1 || exit 0

input="$(cat)"
active="$(printf '%s' "$input" | jq -r '.stop_hook_active // false' 2>/dev/null || echo false)"
[ "$active" = "true" ] && exit 0

root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

list="$(mktemp)"
trap 'rm -f "$list"' EXIT
(cd "$root" && {
	git diff --name-only -z
	git diff --name-only --cached -z
	git ls-files --others --exclude-standard -z
} 2>/dev/null) | tr '\0' '\n' >"$list"

changed=""
while IFS= read -r rel; do
	[ -n "$rel" ] || continue
	[ -f "$root/$rel" ] || continue
	case "$rel" in
	*.rs) changed="${changed}${rel}${nl}" ;;
	esac
done <"$list"
[ -n "$changed" ] || exit 0

(cd / && cargo --version >/dev/null 2>&1) || exit 0
(cd / && cargo clippy --version >/dev/null 2>&1) || exit 0

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

printf '%s' "$changed" >"$list"
workspaces="$(while IFS= read -r rel; do
	[ -n "$rel" ] || continue
	dir="$root/$(dirname -- "$rel")"
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
			probe="$(dirname -- "$probe")"
		done
	fi
	[ -n "$manifest" ] && dirname -- "$manifest"
done <"$list" | sort -u)"
[ -n "$workspaces" ] || exit 0

errors=""
broken=""
warncount=0
printf '%s' "$workspaces" >"$list"
while IFS= read -r ws; do
	[ -n "$ws" ] || continue
	out="$(cd "$ws" && cargo clippy --workspace --all-targets --color=never --message-format=json 2>/dev/null)"
	rc=$?
	# a clippy that never ran writes nothing and exits non-zero, which reads as clean
	if [ "$rc" -ge 2 ] || [ -z "$out" ]; then
		broken="${broken}- ${ws}: cargo clippy exited ${rc} without a usable report${nl}"
		continue
	fi
	found="$(printf '%s' "$out" | jq -r --arg ws "$ws" '
    select(.reason == "compiler-message")
    | .message
    | select(.level == "error")
    | . as $m
    | (([.spans[]? | select(.is_primary)] | first) // null) as $s
    | if $s then
        (if ($s.file_name | startswith("/")) then $s.file_name else "\($ws)/\($s.file_name)" end)
        + ":\($s.line_start):\($s.column_start): \($m.message)"
      else $m.message end
  ' 2>/dev/null | grep -v '^aborting due to' || true)"
	[ -n "$found" ] && errors="${errors}${found}${nl}"
	n="$(printf '%s' "$out" | jq -r '
    select(.reason == "compiler-message") | .message | select(.level == "warning") | .message
  ' 2>/dev/null | grep -c . || true)"
	warncount=$((warncount + ${n:-0}))
done <"$list"

errors="$(printf '%s' "$errors" | grep -v '^$' | awk '!seen[$0]++' || true)"

if [ -z "$errors" ] && [ -z "$broken" ]; then
	exit 0
fi

reason="devops-lsp Rust gate:"
if [ -n "$broken" ]; then
	reason="${reason}${nl}The check did not complete for some workspaces. Treat these as unverified, not clean:${nl}${broken}"
fi
if [ -n "$errors" ]; then
	total="$(printf '%s\n' "$errors" | wc -l | tr -d ' ')"
	shown="$(printf '%s\n' "$errors" | head -40)"
	[ "$total" -gt 40 ] && shown="${shown}${nl}... $((total - 40)) more"
	reason="${reason}${nl}'cargo clippy --workspace --all-targets' reported ${total} error(s). Fix them before finishing:${nl}${shown}"
fi
[ "$warncount" -gt 0 ] && reason="${reason}${nl}${nl}There are also ${warncount} clippy warning(s)."

jq -n --arg r "$reason" '{decision: "block", reason: $r}'
exit 0
