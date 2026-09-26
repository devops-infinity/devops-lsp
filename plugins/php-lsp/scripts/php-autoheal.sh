#!/bin/sh
set -u

nl='
'

command -v jq >/dev/null 2>&1 || exit 0

input="$(cat)"
file="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)"

case "$file" in
*.blade.php) exit 0 ;;
*.php | *.phtml | *.php3 | *.php4 | *.php5 | *.php7 | *.php8 | *.phps) ;;
*) exit 0 ;;
esac
[ -f "$file" ] || exit 0

dir="$(cd "$(dirname -- "$file")" 2>/dev/null && pwd)" || exit 0

root=""
probe="$dir"
while [ -n "$probe" ] && [ "$probe" != "/" ]; do
	if [ -f "$probe/composer.json" ]; then
		root="$probe"
		break
	fi
	probe="$(dirname -- "$probe")"
done
[ -n "$root" ] || root="$dir"

if command -v php >/dev/null 2>&1; then
	if ! lint="$(php -l "$file" 2>&1)"; then
		ctx="devops-lsp auto-heal: 'php -l' found a syntax error in ${file}. Nothing else ran. Fix it:${nl}${lint}"
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

out=""
fmt_rc=0
if [ -f "$root/pint.json" ] || [ -x "$root/vendor/bin/pint" ]; then
	p="$(bin pint)"
	if [ -n "$p" ]; then
		out="$(cd "$root" && "$p" --repair "$file" 2>&1)"
		fmt_rc=$?
	fi
elif [ -f "$root/.php-cs-fixer.php" ] || [ -f "$root/.php-cs-fixer.dist.php" ]; then
	p="$(bin php-cs-fixer)"
	if [ -n "$p" ]; then
		# the default path-mode overrides the config's Finder, reformatting excluded files
		out="$(cd "$root" && "$p" fix --path-mode=intersection --using-cache=no --quiet "$file" 2>&1)"
		fmt_rc=$?
	fi
elif [ -f "$root/phpcs.xml" ] || [ -f "$root/phpcs.xml.dist" ]; then
	p="$(bin phpcbf)"
	if [ -n "$p" ]; then
		out="$(cd "$root" && "$p" -q "$file" 2>&1)"
		fmt_rc=$?
	fi
else
	p="$(bin pint)"
	if [ -n "$p" ]; then
		out="$(cd "$root" && "$p" --repair "$file" 2>&1)"
		fmt_rc=$?
	fi
fi

if [ "$fmt_rc" -ge 2 ]; then
	ctx="devops-lsp auto-heal ran the project's formatter on ${file} and it exited ${fmt_rc}. The formatting did not complete:${nl}${out}"
	jq -n --arg c "$ctx" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $c}}'
	exit 0
fi

if printf '%s' "$out" | jq -e '.tool == "pint"' >/dev/null 2>&1; then
	errs="$(printf '%s' "$out" | jq -r '(.errors // [])[] | "\(.path): \(.message)"' 2>/dev/null || true)"
	[ -n "$errs" ] || exit 0
	ctx="devops-lsp auto-heal: Pint reported errors on ${file}:${nl}${errs}"
	jq -n --arg c "$ctx" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $c}}'
fi
exit 0
