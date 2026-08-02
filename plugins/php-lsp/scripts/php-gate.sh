#!/usr/bin/env bash
set -uo pipefail

input="$(cat)"
active="$(printf '%s' "$input" | jq -r '.stop_hook_active // false' 2>/dev/null || echo false)"
[ "$active" = "true" ] && exit 0

root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

changed="$(cd "$root" && git status --porcelain 2>/dev/null |
	sed -E 's/^.{3}//; s/^.* -> //; s/^"(.*)"$/\1/' | grep -E '\.(php|phtml)$' | grep -v '\.blade\.php$' || true)"
[ -n "$changed" ] || exit 0

projects="$(printf '%s\n' "$changed" | while IFS= read -r rel; do
	dir="$root/$(dirname "$rel")"
	[ -d "$dir" ] || continue
	probe="$(cd "$dir" && pwd)"
	while [ -n "$probe" ] && [ "$probe" != "/" ]; do
		if [ -f "$probe/composer.json" ]; then
			printf '%s\n' "$probe"
			break
		fi
		probe="$(dirname "$probe")"
	done
done | sort -u)"
[ -n "$projects" ] || exit 0

errors=""
broken=""
while IFS= read -r proj; do
	[ -n "$proj" ] || continue

	phpstan=""
	if [ -x "$proj/vendor/bin/phpstan" ]; then
		phpstan="$proj/vendor/bin/phpstan"
	elif command -v phpstan >/dev/null 2>&1; then
		phpstan="$(command -v phpstan)"
	fi
	[ -n "$phpstan" ] || continue

	# Without a config file PHPStan silently runs at level 0 and exits 0 on almost
	# anything, which reads as a clean project. Pass a real level instead, and say so.
	level_note=""
	if [ -f "$proj/phpstan.neon" ] || [ -f "$proj/phpstan.neon.dist" ] || [ -f "$proj/phpstan.dist.neon" ]; then
		out="$(cd "$proj" && "$phpstan" analyse --error-format=json --no-progress --no-interaction --memory-limit=2G 2>/tmp/.devops-php-gate-err)"
	else
		out="$(cd "$proj" && "$phpstan" analyse --level=5 --error-format=json --no-progress --no-interaction --memory-limit=2G . 2>/tmp/.devops-php-gate-err)"
		level_note=" (no phpstan.neon found, ran at level 5)"
	fi
	status=$?
	err="$(cat /tmp/.devops-php-gate-err 2>/dev/null || true)"
	rm -f /tmp/.devops-php-gate-err

	# Exit 1 means either real findings or a setup failure, so the JSON decides.
	if ! printf '%s' "$out" | jq -e 'has("totals")' >/dev/null 2>&1; then
		broken="$broken- ${proj}: PHPStan exited ${status} without a usable report"$'\n'
		[ -n "$err" ] && broken="$broken  $(printf '%s' "$err" | head -n1)"$'\n'
		continue
	fi

	found="$(printf '%s' "$out" | jq -r '
    (.files // {}) | to_entries[]
    | .key as $f
    | (.value.messages // [])[]
    | "\($f):\(.line // 0): \(.message)"
  ' 2>/dev/null || true)"
	general="$(printf '%s' "$out" | jq -r '(.errors // [])[]' 2>/dev/null || true)"

	[ -n "$found" ] && errors="$errors$found$level_note"$'\n'
	[ -n "$general" ] && errors="$errors$general"$'\n'
done <<EOF
$projects
EOF

errors="$(printf '%s' "$errors" | grep -v '^$' | awk '!seen[$0]++' || true)"

if [ -z "$errors" ] && [ -z "$broken" ]; then
	exit 0
fi

reason="devops-lsp PHP gate:"
if [ -n "$broken" ]; then
	reason="$reason"$'\n'"The check did not complete for some projects. Treat these as unverified, not clean:"$'\n'"$broken"
fi
if [ -n "$errors" ]; then
	total="$(printf '%s\n' "$errors" | wc -l | tr -d ' ')"
	shown="$(printf '%s\n' "$errors" | head -40)"
	[ "$total" -gt 40 ] && shown="$shown"$'\n'"... $((total - 40)) more"
	reason="$reason"$'\n'"PHPStan reported ${total} error(s). Fix them before finishing:"$'\n'"$shown"
fi

jq -n --arg r "$reason" '{decision: "block", reason: $r}'
exit 0
