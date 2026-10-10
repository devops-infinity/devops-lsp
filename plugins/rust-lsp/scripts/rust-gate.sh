#!/bin/sh
# Whole-workspace cargo clippy gate: block with the errors it reports; a clippy that cannot run is never read as a pass.
set -u

newline='
'

command -v jq >/dev/null 2>&1 || exit 0
command -v git >/dev/null 2>&1 || exit 0

if [ -t 0 ]; then
	printf 'usage: echo ...hook JSON... | %s\n' "$0" >&2
	exit 0
fi

script_dir="$(cd "$(dirname -- "$0")" && pwd)" || exit 0
# shellcheck disable=SC1091  # resolved beside this script; shellcheck cannot follow the dynamic path
. "$script_dir/toolchain-pin.sh"

block_with_reason() {
	jq -n --arg reason "$1" '{decision: "block", reason: $reason}'
}

hook_input="$(cat)"
stop_hook_active="$(printf '%s' "$hook_input" | jq -r '.stop_hook_active // false' 2>/dev/null || echo false)"
[ "$stop_hook_active" = "true" ] && exit 0

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

git_nul_file="$(mktemp)" || exit 0
scratch_file="$(mktemp)" || exit 0
trap 'rm -f "$git_nul_file" "$scratch_file"' EXIT HUP INT TERM

if ! (cd "$repo_root" && {
	git diff --name-only -z || exit 1
	git diff --name-only --cached -z || exit 1
	git ls-files --others --exclude-standard -z || exit 1
} 2>/dev/null) >"$git_nul_file"; then
	block_with_reason "devops-lsp Rust gate: git could not list the changed files, so the check did not happen. Treat this as unverified, not clean."
	exit 0
fi
# POSIX sh has no NUL-safe string handling; filenames containing a newline are outside this line protocol
tr '\0' '\n' <"$git_nul_file" >"$scratch_file"

changed_files=""
while IFS= read -r rel_path; do
	[ -n "$rel_path" ] || continue
	[ -f "$repo_root/$rel_path" ] || continue
	case "$rel_path" in
	*.rs) changed_files="${changed_files}${rel_path}${newline}" ;;
	esac
done <"$scratch_file"
[ -n "$changed_files" ] || exit 0

(cd / && cargo --version >/dev/null 2>&1) || exit 0
(cd / && cargo clippy --version >/dev/null 2>&1) || exit 0

printf '%s' "$changed_files" >"$scratch_file"
workspace_dirs="$(while IFS= read -r rel_path; do
	[ -n "$rel_path" ] || continue
	file_dir="$repo_root/$(dirname -- "$rel_path")"
	[ -d "$file_dir" ] || continue
	pinned_toolchain_missing "$file_dir" && continue
	manifest="$(cd "$file_dir" && cargo locate-project --workspace --message-format plain </dev/null 2>/dev/null || true)"
	if [ -z "$manifest" ]; then
		manifest_walk_dir="$file_dir"
		while [ -n "$manifest_walk_dir" ] && [ "$manifest_walk_dir" != "/" ]; do
			if [ -f "$manifest_walk_dir/Cargo.toml" ]; then
				manifest="$manifest_walk_dir/Cargo.toml"
				break
			fi
			manifest_walk_dir="$(dirname -- "$manifest_walk_dir")"
		done
	fi
	[ -n "$manifest" ] && dirname -- "$manifest"
done <"$scratch_file" | sort -u)"
[ -n "$workspace_dirs" ] || exit 0

error_lines=""
unverified=""
warning_count=0
# the trailing newline matters: command substitution strips it, and a final unterminated line is dropped by read
printf '%s\n' "$workspace_dirs" >"$scratch_file"
while IFS= read -r workspace_dir; do
	[ -n "$workspace_dir" ] || continue
	clippy_json="$(cd "$workspace_dir" && cargo clippy --workspace --all-targets --color=never --message-format=json </dev/null 2>/dev/null)"
	clippy_exit=$?
	# cargo reports a failed build as exit 101 with a full JSON report, so the report, not the exit code, decides
	if [ -z "$clippy_json" ]; then
		unverified="${unverified}- ${workspace_dir}: cargo clippy exited ${clippy_exit} without a usable report${newline}"
		continue
	fi
	if ! raw_error_lines="$(printf '%s' "$clippy_json" | jq -r --arg workspace "$workspace_dir" '
		select(.reason == "compiler-message")
		| .message
		| select(.level == "error")
		| . as $msg
		| (([.spans[]? | select(.is_primary)] | first) // null) as $span
		| if $span then
			(if ($span.file_name | startswith("/")) then $span.file_name else "\($workspace)/\($span.file_name)" end)
			+ ":\($span.line_start):\($span.column_start): \($msg.message | gsub("[\\n\\r]+"; " "))"
		  else ($msg.message | gsub("[\\n\\r]+"; " ")) end
	  ' 2>/dev/null)"; then
		unverified="${unverified}- ${workspace_dir}: the clippy report could not be parsed${newline}"
		continue
	fi
	workspace_errors="$(printf '%s' "$raw_error_lines" | grep -v '^aborting due to' || true)"
	[ -n "$workspace_errors" ] && error_lines="${error_lines}${workspace_errors}${newline}"
	new_warnings="$(printf '%s' "$clippy_json" | jq -r '
		select(.reason == "compiler-message") | .message
		| select(.level == "warning")
		| .message
		| select(test(" warnings? emitted$") | not)
		| gsub("[\\n\\r]+"; " ")
	' 2>/dev/null | grep -c . || true)"
	warning_count=$((warning_count + ${new_warnings:-0}))
done <"$scratch_file"

error_lines="$(printf '%s' "$error_lines" | grep -v '^$' | awk '!seen[$0]++' || true)"

if [ -z "$error_lines" ] && [ -z "$unverified" ]; then
	exit 0
fi

reason="devops-lsp Rust gate:"
if [ -n "$unverified" ]; then
	reason="${reason}${newline}The check did not complete for some workspaces. Treat these as unverified, not clean:${newline}${unverified}"
fi
if [ -n "$error_lines" ]; then
	error_total="$(printf '%s\n' "$error_lines" | wc -l | tr -d ' ')"
	shown_errors="$(printf '%s\n' "$error_lines" | head -n 40)"
	[ "$error_total" -gt 40 ] && shown_errors="${shown_errors}${newline}... $((error_total - 40)) more"
	reason="${reason}${newline}'cargo clippy --workspace --all-targets' reported ${error_total} error(s). Fix them before finishing:${newline}${shown_errors}"
fi
[ "$warning_count" -gt 0 ] && reason="${reason}${newline}${newline}There are also ${warning_count} clippy warning(s)."

block_with_reason "$reason"
exit 0
