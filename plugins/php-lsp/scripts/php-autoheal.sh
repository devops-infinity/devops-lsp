#!/usr/bin/env bash
set -uo pipefail

input="$(cat)"
file="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)"

case "$file" in
*.blade.php) exit 0 ;;
*.php | *.phtml | *.php3 | *.php4 | *.php5 | *.php7 | *.php8 | *.phps) ;;
*) exit 0 ;;
esac
[ -f "$file" ] || exit 0

dir="$(cd "$(dirname "$file")" 2>/dev/null && pwd)" || exit 0

root=""
probe="$dir"
while [ -n "$probe" ] && [ "$probe" != "/" ]; do
	if [ -f "$probe/composer.json" ]; then
		root="$probe"
		break
	fi
	probe="$(dirname "$probe")"
done
[ -n "$root" ] || root="$dir"

# Parse check first. It is cheap and it turns a confusing downstream formatter error
# into a clear one. Note the exit code: php -l returns 255 on a parse error, not 1.
if command -v php >/dev/null 2>&1; then
	if ! lint="$(php -l "$file" 2>&1)"; then
		ctx="devops-lsp auto-heal: 'php -l' found a syntax error in ${file}. Nothing else ran. Fix it:"$'\n'"$lint"
		jq -n --arg c "$ctx" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $c}}'
		exit 0
	fi
fi

bin() {
	if [ -x "$root/vendor/bin/$1" ]; then
		printf '%s' "$root/vendor/bin/$1"
	elif command -v "$1" >/dev/null 2>&1; then
		command -v "$1"
	fi
}

# Exactly one formatter runs, chosen by what the project actually configured.
out=""
if [ -f "$root/pint.json" ] || [ -x "$root/vendor/bin/pint" ]; then
	p="$(bin pint)"
	[ -n "$p" ] && out="$(cd "$root" && "$p" --repair "$file" 2>&1 || true)"
elif [ -f "$root/.php-cs-fixer.php" ] || [ -f "$root/.php-cs-fixer.dist.php" ]; then
	p="$(bin php-cs-fixer)"
	# --path-mode=intersection is required. The default, override, makes an explicit
	# path argument ignore the config's own Finder, so the hook would happily
	# reformat files the project deliberately excluded.
	[ -n "$p" ] && out="$(cd "$root" && "$p" fix --path-mode=intersection --using-cache=no --quiet "$file" 2>&1 || true)"
elif [ -f "$root/phpcs.xml" ] || [ -f "$root/phpcs.xml.dist" ]; then
	p="$(bin phpcbf)"
	[ -n "$p" ] && out="$(cd "$root" && "$p" -q "$file" 2>&1 || true)"
else
	# No declared style, so use Pint's own default preset rather than forcing psr12,
	# which leaves obvious mess behind (it does not collapse `return   $a;`).
	p="$(bin pint)"
	[ -n "$p" ] && out="$(cd "$root" && "$p" --repair "$file" 2>&1 || true)"
fi

# Pint detects Claude Code and emits its own agent-shaped JSON regardless of any
# --format flag, so read that shape rather than trying to force another one.
if printf '%s' "$out" | jq -e '.tool == "pint"' >/dev/null 2>&1; then
	errs="$(printf '%s' "$out" | jq -r '(.errors // [])[] | "\(.path): \(.message)"' 2>/dev/null || true)"
	[ -n "$errs" ] || exit 0
	ctx="devops-lsp auto-heal: Pint reported errors on ${file}:"$'\n'"$errs"
	jq -n --arg c "$ctx" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $c}}'
fi
exit 0
