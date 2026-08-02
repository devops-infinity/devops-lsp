#!/usr/bin/env bash
set -uo pipefail

input="$(cat)"
active="$(printf '%s' "$input" | jq -r '.stop_hook_active // false' 2>/dev/null || echo false)"
[ "$active" = "true" ] && exit 0

root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

changed="$(cd "$root" && git status --porcelain 2>/dev/null |
	sed -E 's/^.{3}//; s/^.* -> //; s/^"(.*)"$/\1/' | grep -E '\.pyi?$' || true)"
[ -n "$changed" ] || exit 0

command -v basedpyright >/dev/null 2>&1 || exit 0

# Every Python project touched by a changed file. A project does not have to sit at the
# git root, and one repo can hold several, so resolve them from the files themselves.
projects="$(printf '%s\n' "$changed" | while IFS= read -r rel; do
	dir="$root/$(dirname "$rel")"
	[ -d "$dir" ] || continue
	probe="$(cd "$dir" && pwd)"
	while [ -n "$probe" ] && [ "$probe" != "/" ]; do
		for marker in pyproject.toml setup.py setup.cfg; do
			if [ -f "$probe/$marker" ]; then
				printf '%s\n' "$probe"
				break 3
			fi
		done
		probe="$(dirname "$probe")"
	done
done | sort -u)"
[ -n "$projects" ] || exit 0

errors=""
broken=""
while IFS= read -r proj; do
	[ -n "$proj" ] || continue

	# basedpyright looks for ./.venv relative to the project root and ignores
	# VIRTUAL_ENV entirely. Without the right interpreter every third-party import
	# resolves to nothing, and the file reads as broken when it is fine.
	interp=""
	for cand in "$proj/.venv/bin/python" "$proj/venv/bin/python" "$proj/.venv/Scripts/python.exe"; do
		[ -x "$cand" ] && interp="$cand" && break
	done
	[ -z "$interp" ] && [ -n "${VIRTUAL_ENV:-}" ] && [ -x "$VIRTUAL_ENV/bin/python" ] && interp="$VIRTUAL_ENV/bin/python"

	if [ -n "$interp" ]; then
		out="$(cd "$proj" && basedpyright --outputjson --pythonpath "$interp" 2>/tmp/.devops-py-gate-err)"
	else
		out="$(cd "$proj" && basedpyright --outputjson 2>/tmp/.devops-py-gate-err)"
	fi
	status=$?
	err="$(cat /tmp/.devops-py-gate-err 2>/dev/null || true)"
	rm -f /tmp/.devops-py-gate-err

	# 0 clean, 1 diagnostics reported. Anything else means the run did not happen -
	# 4 is "file or directory does not exist", and it writes ZERO bytes to stdout, so
	# a pipeline that only reads stdout sees no errors and reports the project clean.
	if [ "$status" -ge 2 ] || ! printf '%s' "$out" | jq -e 'has("summary")' >/dev/null 2>&1; then
		broken="$broken- ${proj}: basedpyright exited ${status} without a usable report"$'\n'
		[ -n "$err" ] && broken="$broken  ${err%%$'\n'*}"$'\n'
		continue
	fi

	# Config problems are reported on stderr with a zero or one exit and valid JSON on
	# stdout, so a silently-ignored setting looks exactly like a healthy run.
	case "$err" in
	*"unrecognized setting"* | *'invalid "'* | *"could not be parsed"*)
		broken="$broken- ${proj}: configuration was rejected, so the check ran with different settings than intended"$'\n'"  ${err%%$'\n'*}"$'\n'
		;;
	esac

	found="$(printf '%s' "$out" | jq -r '
    (.generalDiagnostics // [])[]
    | select(.severity == "error")
    | "\(.file):\((.range.start.line // 0) + 1):\((.range.start.character // 0) + 1): \(.message | split("\n")[0])"
  ' 2>/dev/null || true)"
	[ -n "$found" ] && errors="$errors$found"$'\n'
done <<EOF
$projects
EOF

errors="$(printf '%s' "$errors" | grep -v '^$' | awk '!seen[$0]++' || true)"

if [ -z "$errors" ] && [ -z "$broken" ]; then
	exit 0
fi

reason="devops-lsp Python gate:"
if [ -n "$broken" ]; then
	reason="$reason"$'\n'"The check did not complete for some projects. Treat these as unverified, not clean:"$'\n'"$broken"
fi
if [ -n "$errors" ]; then
	total="$(printf '%s\n' "$errors" | wc -l | tr -d ' ')"
	shown="$(printf '%s\n' "$errors" | head -40)"
	[ "$total" -gt 40 ] && shown="$shown"$'\n'"... $((total - 40)) more"
	reason="$reason"$'\n'"basedpyright reported ${total} error(s). Fix them before finishing:"$'\n'"$shown"
fi

jq -n --arg r "$reason" '{decision: "block", reason: $r}'
exit 0
