#!/bin/sh
# Whole-project basedpyright gate: block with the errors it reports; a run that cannot happen is never read as a pass.
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
	block_with_reason "devops-lsp Python gate: git could not list the changed files, so the check did not happen. Treat this as unverified, not clean."
	exit 0
fi
# POSIX sh has no NUL-safe string handling; filenames containing a newline are outside this line protocol
tr '\0' '\n' <"$git_nul_file" >"$scratch_file"

changed_files=""
while IFS= read -r rel_path; do
	[ -n "$rel_path" ] || continue
	[ -f "$repo_root/$rel_path" ] || continue
	case "$rel_path" in
	*.py | *.pyi) changed_files="${changed_files}${rel_path}${newline}" ;;
	esac
done <"$scratch_file"
[ -n "$changed_files" ] || exit 0

command -v basedpyright >/dev/null 2>&1 || exit 0

printf '%s' "$changed_files" >"$scratch_file"
project_dirs="$(while IFS= read -r rel_path; do
	[ -n "$rel_path" ] || continue
	file_dir="$repo_root/$(dirname -- "$rel_path")"
	[ -d "$file_dir" ] || continue
	walk_dir="$(cd "$file_dir" && pwd)"
	while [ -n "$walk_dir" ] && [ "$walk_dir" != "/" ]; do
		for marker in pyproject.toml setup.py setup.cfg; do
			if [ -f "$walk_dir/$marker" ]; then
				printf '%s\n' "$walk_dir"
				break 2
			fi
		done
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

	venv_python=""
	for candidate in "$project_dir/.venv/bin/python" "$project_dir/venv/bin/python" "$project_dir/.venv/Scripts/python.exe"; do
		[ -x "$candidate" ] && venv_python="$candidate" && break
	done
	if [ -z "$venv_python" ] && [ -n "${VIRTUAL_ENV:-}" ] && [ -x "$VIRTUAL_ENV/bin/python" ]; then
		# an inherited VIRTUAL_ENV belongs to this project only when it lives under it
		case "$VIRTUAL_ENV" in
		"$project_dir"/*) venv_python="$VIRTUAL_ENV/bin/python" ;;
		esac
	fi

	if [ -n "$venv_python" ]; then
		pyright_json="$(cd "$project_dir" && basedpyright --outputjson --pythonpath "$venv_python" </dev/null 2>"$stderr_file")"
	else
		pyright_json="$(cd "$project_dir" && basedpyright --outputjson </dev/null 2>"$stderr_file")"
	fi
	pyright_exit=$?
	stderr_text="$(cat "$stderr_file" 2>/dev/null || true)"
	: >"$stderr_file"

	if [ "$pyright_exit" -ge 2 ] ||
		# basedpyright exits 4 with zero bytes on stdout, which reads as a clean project
		! printf '%s' "$pyright_json" | jq -e 'has("summary") and has("generalDiagnostics")' >/dev/null 2>&1; then
		unverified="${unverified}- ${project_dir}: basedpyright exited ${pyright_exit} without a usable report${newline}"
		[ -n "$stderr_text" ] && unverified="${unverified}  ${stderr_text%%"${newline}"*}${newline}"
		continue
	fi

	case "$stderr_text" in
	*"unrecognized setting"* | *'invalid "'* | *"could not be parsed"*)
		unverified="${unverified}- ${project_dir}: configuration was rejected, so the check ran with different settings than intended${newline}  ${stderr_text%%"${newline}"*}${newline}"
		;;
	esac

	file_errors="$(printf '%s' "$pyright_json" | jq -r '
		(.generalDiagnostics // [])[]
		| select(.severity == "error")
		| "\(.file):\((.range.start.line // 0) + 1):\((.range.start.character // 0) + 1): \(.message | split("\n")[0])"
	' 2>/dev/null || true)"
	[ -n "$file_errors" ] && error_lines="${error_lines}${file_errors}${newline}"
done <"$scratch_file"

error_lines="$(printf '%s' "$error_lines" | grep -v '^$' | awk '!seen[$0]++' || true)"

if [ -z "$error_lines" ] && [ -z "$unverified" ]; then
	exit 0
fi

reason="devops-lsp Python gate:"
if [ -n "$unverified" ]; then
	reason="${reason}${newline}The check did not complete for some projects. Treat these as unverified, not clean:${newline}${unverified}"
fi
if [ -n "$error_lines" ]; then
	error_total="$(printf '%s\n' "$error_lines" | wc -l | tr -d ' ')"
	shown_errors="$(printf '%s\n' "$error_lines" | head -n 40)"
	[ "$error_total" -gt 40 ] && shown_errors="${shown_errors}${newline}... $((error_total - 40)) more"
	reason="${reason}${newline}basedpyright reported ${error_total} error(s). Fix them before finishing:${newline}${shown_errors}"
fi

block_with_reason "$reason"
exit 0
