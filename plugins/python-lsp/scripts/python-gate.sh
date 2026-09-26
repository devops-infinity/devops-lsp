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
errfile="$(mktemp)"
trap 'rm -f "$list" "$errfile"' EXIT
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
	*.py | *.pyi) changed="${changed}${rel}${nl}" ;;
	esac
done <"$list"
[ -n "$changed" ] || exit 0

command -v basedpyright >/dev/null 2>&1 || exit 0

printf '%s' "$changed" >"$list"
projects="$(while IFS= read -r rel; do
	[ -n "$rel" ] || continue
	dir="$root/$(dirname -- "$rel")"
	[ -d "$dir" ] || continue
	probe="$(cd "$dir" && pwd)"
	while [ -n "$probe" ] && [ "$probe" != "/" ]; do
		for marker in pyproject.toml setup.py setup.cfg; do
			if [ -f "$probe/$marker" ]; then
				printf '%s\n' "$probe"
				break 3
			fi
		done
		probe="$(dirname -- "$probe")"
	done
done <"$list" | sort -u)"
[ -n "$projects" ] || exit 0

errors=""
broken=""
printf '%s' "$projects" >"$list"
while IFS= read -r proj; do
	[ -n "$proj" ] || continue

	interp=""
	for cand in "$proj/.venv/bin/python" "$proj/venv/bin/python" "$proj/.venv/Scripts/python.exe"; do
		[ -x "$cand" ] && interp="$cand" && break
	done
	[ -z "$interp" ] && [ -n "${VIRTUAL_ENV:-}" ] && [ -x "$VIRTUAL_ENV/bin/python" ] && interp="$VIRTUAL_ENV/bin/python"

	if [ -n "$interp" ]; then
		out="$(cd "$proj" && basedpyright --outputjson --pythonpath "$interp" 2>"$errfile")"
	else
		out="$(cd "$proj" && basedpyright --outputjson 2>"$errfile")"
	fi
	rc=$?
	err="$(cat "$errfile" 2>/dev/null || true)"
	: >"$errfile"

	if [ "$rc" -ge 2 ] ||
		# basedpyright exits 4 with zero bytes on stdout, which reads as a clean project
		! printf '%s' "$out" | jq -e 'has("summary") and has("generalDiagnostics")' >/dev/null 2>&1; then
		broken="${broken}- ${proj}: basedpyright exited ${rc} without a usable report${nl}"
		[ -n "$err" ] && broken="${broken}  ${err%%"${nl}"*}${nl}"
		continue
	fi

	case "$err" in
	*"unrecognized setting"* | *'invalid "'* | *"could not be parsed"*)
		broken="${broken}- ${proj}: configuration was rejected, so the check ran with different settings than intended${nl}  ${err%%"${nl}"*}${nl}"
		;;
	esac

	found="$(printf '%s' "$out" | jq -r '
    (.generalDiagnostics // [])[]
    | select(.severity == "error")
    | "\(.file):\((.range.start.line // 0) + 1):\((.range.start.character // 0) + 1): \(.message | split("\n")[0])"
  ' 2>/dev/null || true)"
	[ -n "$found" ] && errors="${errors}${found}${nl}"
done <"$list"

errors="$(printf '%s' "$errors" | grep -v '^$' | awk '!seen[$0]++' || true)"

if [ -z "$errors" ] && [ -z "$broken" ]; then
	exit 0
fi

reason="devops-lsp Python gate:"
if [ -n "$broken" ]; then
	reason="${reason}${nl}The check did not complete for some projects. Treat these as unverified, not clean:${nl}${broken}"
fi
if [ -n "$errors" ]; then
	total="$(printf '%s\n' "$errors" | wc -l | tr -d ' ')"
	shown="$(printf '%s\n' "$errors" | head -40)"
	[ "$total" -gt 40 ] && shown="${shown}${nl}... $((total - 40)) more"
	reason="${reason}${nl}basedpyright reported ${total} error(s). Fix them before finishing:${nl}${shown}"
fi

jq -n --arg r "$reason" '{decision: "block", reason: $r}'
exit 0
