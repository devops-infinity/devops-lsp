#!/bin/sh
# Whole-project PHPStan gate: block with the errors it reports; a run that cannot happen is never read as a pass.
set -u

newline='
'

command -v jq >/dev/null 2>&1 || exit 0
command -v git >/dev/null 2>&1 || exit 0

if [ -t 0 ]; then
	printf 'usage: echo ...hook JSON... | %s\n' "$0" >&2
	exit 0
fi

block_with_reason() {
	jq -n --arg reason "$1" '{decision: "block", reason: $reason}'
}

hook_input="$(cat)"
stop_hook_active="$(printf '%s' "$hook_input" | jq -r '.stop_hook_active // false' 2>/dev/null || echo false)"
[ "$stop_hook_active" = "true" ] && exit 0

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

git_nul_file="$(mktemp)" || exit 0
scratch_file="$(mktemp)" || exit 0
stderr_file="$(mktemp)" || exit 0
trap 'rm -f "$git_nul_file" "$scratch_file" "$stderr_file"' EXIT HUP INT TERM

if ! (cd "$repo_root" && {
	git diff --name-only -z || exit 1
	git diff --name-only --cached -z || exit 1
	git ls-files --others --exclude-standard -z || exit 1
} 2>/dev/null) >"$git_nul_file"; then
	block_with_reason "devops-lsp PHP gate: git could not list the changed files, so the check did not happen. Treat this as unverified, not clean."
	exit 0
fi
# POSIX sh has no NUL-safe string handling; filenames containing a newline are outside this line protocol
tr '\0' '\n' <"$git_nul_file" >"$scratch_file"

changed_files=""
while IFS= read -r rel_path; do
	[ -n "$rel_path" ] || continue
	[ -f "$repo_root/$rel_path" ] || continue
	case "$rel_path" in
	*.php | *.phtml)
		case "$rel_path" in
		*.blade.php) continue ;;
		esac
		changed_files="${changed_files}${rel_path}${newline}"
		;;
	esac
done <"$scratch_file"
[ -n "$changed_files" ] || exit 0

printf '%s' "$changed_files" >"$scratch_file"
project_dirs="$(while IFS= read -r rel_path; do
	[ -n "$rel_path" ] || continue
	file_dir="$repo_root/$(dirname -- "$rel_path")"
	[ -d "$file_dir" ] || continue
	walk_dir="$(cd "$file_dir" && pwd)"
	while [ -n "$walk_dir" ] && [ "$walk_dir" != "/" ]; do
		if [ -f "$walk_dir/composer.json" ]; then
			printf '%s\n' "$walk_dir"
			break
		fi
		walk_dir="$(dirname -- "$walk_dir")"
	done
done <"$scratch_file" | sort -u)"
[ -n "$project_dirs" ] || exit 0

error_lines=""
unverified=""
# the trailing newline matters: command substitution strips it, and a final unterminated line is dropped by read
printf '%s\n' "$project_dirs" >"$scratch_file"
while IFS= read -r project_dir; do
	[ -n "$project_dir" ] || continue

	phpstan_bin=""
	if [ -x "$project_dir/vendor/bin/phpstan" ]; then
		phpstan_bin="$project_dir/vendor/bin/phpstan"
	elif command -v phpstan >/dev/null 2>&1; then
		phpstan_bin="$(command -v phpstan)"
	fi
	[ -n "$phpstan_bin" ] || continue

	level_suffix=""
	if [ -f "$project_dir/phpstan.neon" ] || [ -f "$project_dir/phpstan.neon.dist" ] || [ -f "$project_dir/phpstan.dist.neon" ]; then
		phpstan_json="$(cd "$project_dir" && "$phpstan_bin" analyse --error-format=json --no-progress --no-interaction --memory-limit=2G </dev/null 2>"$stderr_file")"
		phpstan_exit=$?
	else
		phpstan_json="$(cd "$project_dir" && "$phpstan_bin" analyse --level=5 --error-format=json --no-progress --no-interaction --memory-limit=2G . </dev/null 2>"$stderr_file")"
		phpstan_exit=$?
		level_suffix=" (no phpstan.neon found, ran at level 5)"
	fi
	stderr_text="$(cat "$stderr_file" 2>/dev/null || true)"
	: >"$stderr_file"

	# PHPStan exits 1 for findings and for a setup failure alike, so the JSON decides
	if ! printf '%s' "$phpstan_json" | jq -e 'has("totals")' >/dev/null 2>&1; then
		unverified="${unverified}- ${project_dir}: PHPStan exited ${phpstan_exit} without a usable report${newline}"
		[ -n "$stderr_text" ] && unverified="${unverified}  $(printf '%s' "$stderr_text" | head -n1)${newline}"
		continue
	fi

	file_findings="$(printf '%s' "$phpstan_json" | jq -r '
	(.files // {}) | to_entries[]
	| .key as $file
	| (.value.messages // [])[]
	| "\($file):\(.line // 0): \(.message)"
  ' 2>/dev/null || true)"
	top_level_errors="$(printf '%s' "$phpstan_json" | jq -r '(.errors // [])[]' 2>/dev/null || true)"

	[ -n "$file_findings" ] && error_lines="${error_lines}${file_findings}${level_suffix}${newline}"
	[ -n "$top_level_errors" ] && error_lines="${error_lines}${top_level_errors}${newline}"
done <"$scratch_file"

error_lines="$(printf '%s' "$error_lines" | grep -v '^$' | awk '!seen[$0]++' || true)"

if [ -z "$error_lines" ] && [ -z "$unverified" ]; then
	exit 0
fi

reason="devops-lsp PHP gate:"
if [ -n "$unverified" ]; then
	reason="${reason}${newline}The check did not complete for some projects. Treat these as unverified, not clean:${newline}${unverified}"
fi
if [ -n "$error_lines" ]; then
	error_total="$(printf '%s\n' "$error_lines" | wc -l | tr -d ' ')"
	shown_errors="$(printf '%s\n' "$error_lines" | head -n 40)"
	[ "$error_total" -gt 40 ] && shown_errors="${shown_errors}${newline}... $((error_total - 40)) more"
	reason="${reason}${newline}PHPStan reported ${error_total} error(s). Fix them before finishing:${newline}${shown_errors}"
fi

block_with_reason "$reason"
exit 0
