#!/usr/bin/env bats
# Hook-script tests: notify silence/reporting, gate guards, and the regressions
# fixed in this suite (clippy exit-101, dropped last project, git failure read as clean).

REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
WORK=""

setup() {
	WORK="$(mktemp -d)"
}

teardown() {
	[ -n "$WORK" ] && rm -rf "$WORK"
}

feed() {
	# feed <script> <stdin-json> ; runs the script as the hook host would
	run sh -c "printf '%s' '$2' | sh '$1'"
}

@test "every notify script stays silent on a non-matching file extension" {
	for script in "$REPO"/plugins/*-lsp/scripts/*-notify.sh; do
		feed "$script" '{"tool_input":{"file_path":"/etc/hosts"}}'
		[ "$status" -eq 0 ]
		[ -z "$output" ]
	done
}

@test "every notify script stays silent on invalid stdin" {
	for script in "$REPO"/plugins/*-lsp/scripts/*-notify.sh; do
		feed "$script" 'not-json'
		[ "$status" -eq 0 ]
		[ -z "$output" ]
	done
}

@test "every gate stays silent when stop_hook_active is true" {
	for script in "$REPO"/plugins/*-lsp/scripts/*-gate.sh; do
		feed "$script" '{"stop_hook_active":true}'
		[ "$status" -eq 0 ]
		[ -z "$output" ]
	done
}

@test "shell-notify reports shellcheck findings and stays silent on a clean file" {
	command -v shellcheck >/dev/null 2>&1 || skip "shellcheck not installed"
	printf '#!/bin/sh\necho $UNQUOTED\n' >"$WORK/bad.sh"
	printf '#!/bin/sh\nprintf "%%s\\n" "quoted"\n' >"$WORK/good.sh"
	feed "$REPO/plugins/shell-lsp/scripts/shell-notify.sh" "{\"tool_input\":{\"file_path\":\"$WORK/bad.sh\"}}"
	[ "$status" -eq 0 ]
	printf '%s' "$output" | jq -e '.hookSpecificOutput.additionalContext | contains("SC2086")' >/dev/null
	feed "$REPO/plugins/shell-lsp/scripts/shell-notify.sh" "{\"tool_input\":{\"file_path\":\"$WORK/good.sh\"}}"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "shell-notify reports nothing for a file with only style findings" {
	command -v shellcheck >/dev/null 2>&1 || skip "shellcheck not installed"
	printf '#!/bin/sh\nexit 0\n' >"$WORK/ok.sh"
	feed "$REPO/plugins/shell-lsp/scripts/shell-notify.sh" "{\"tool_input\":{\"file_path\":\"$WORK/ok.sh\"}}"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "php-notify reports a parse error and never modifies the file" {
	command -v php >/dev/null 2>&1 || skip "php not installed"
	printf '<?php\n$x = ;\n' >"$WORK/bad.php"
	before="$(cat "$WORK/bad.php")"
	feed "$REPO/plugins/php-lsp/scripts/php-notify.sh" "{\"tool_input\":{\"file_path\":\"$WORK/bad.php\"}}"
	[ "$status" -eq 0 ]
	printf '%s' "$output" | jq -e '.hookSpecificOutput.additionalContext | contains("syntax error")' >/dev/null
	[ "$(cat "$WORK/bad.php")" = "$before" ]
}

@test "json-notify reports a prettier problem and never modifies the file" {
	command -v prettier >/dev/null 2>&1 || skip "prettier not installed"
	printf '{ "broken": , }\n' >"$WORK/bad.json"
	before="$(cat "$WORK/bad.json")"
	feed "$REPO/plugins/json-lsp/scripts/json-notify.sh" "{\"tool_input\":{\"file_path\":\"$WORK/bad.json\"}}"
	[ "$status" -eq 0 ]
	printf '%s' "$output" | jq -e '.hookSpecificOutput.additionalContext | length > 0' >/dev/null
	[ "$(cat "$WORK/bad.json")" = "$before" ]
}

@test "json-gate blocks on an unparseable changed file" {
	command -v prettier >/dev/null 2>&1 || skip "prettier not installed"
	git init -q "$WORK/repo"
	printf '{ "broken": , }\n' >"$WORK/repo/bad.json"
	feed "$REPO/plugins/json-lsp/scripts/json-gate.sh" '{"stop_hook_active":false}'
	# the gate must see the fixture: run it with the repo as cwd
	run sh -c "cd '$WORK/repo' && printf '%s' '{\"stop_hook_active\":false}' | sh '$REPO/plugins/json-lsp/scripts/json-gate.sh'"
	[ "$status" -eq 0 ]
	printf '%s' "$output" | jq -e '.decision == "block"' >/dev/null
}

@test "a gate never reads a failed git as a clean pass" {
	# run from outside any git repository: git cannot list changes, so the gate must say unverified
	run sh -c "cd '$WORK' && printf '%s' '{\"stop_hook_active\":false}' | GIT_CEILING_DIRECTORIES='$WORK' sh '$REPO/plugins/json-lsp/scripts/json-gate.sh'"
	[ "$status" -eq 0 ]
	printf '%s' "$output" | jq -e '.reason | contains("unverified, not clean")' >/dev/null
}

@test "rust-gate reports clippy errors even though cargo exits 101" {
	mkdir -p "$WORK/bin" "$WORK/repo/crate/src"
	git init -q "$WORK/repo"
	printf '[package]\nname = "crate"\nedition = "2021"\n' >"$WORK/repo/crate/Cargo.toml"
	printf 'fn main() {}\n' >"$WORK/repo/crate/src/lib.rs"
	cat >"$WORK/bin/cargo" <<'STUB'
#!/bin/sh
[ "$1" = "--version" ] && exit 0
[ "$2" = "--version" ] && exit 0
if [ "$1" = "locate-project" ]; then
	printf '%s\n' "$PWD/Cargo.toml"
	exit 0
fi
printf '%s\n' '{"reason":"compiler-message","message":{"level":"error","message":"cannot find trait `Foo` in this scope","spans":[{"file_name":"src/lib.rs","is_primary":true,"line_start":3,"column_start":10}]}}'
exit 101
STUB
	chmod +x "$WORK/bin/cargo"
	run env PATH="$WORK/bin:$PATH" sh -c "cd '$WORK/repo' && printf '%s' '{\"stop_hook_active\":false}' | sh '$REPO/plugins/rust-lsp/scripts/rust-gate.sh'"
	[ "$status" -eq 0 ]
	printf '%s' "$output" | jq -e '.reason | contains("cannot find trait")' >/dev/null
	# the pre-fix behavior called this "did not complete"; that phrasing must be gone
	printf '%s' "$output" | jq -e '.reason | contains("did not complete") | not' >/dev/null
}

@test "python-gate checks every touched project, including the last one" {
	mkdir -p "$WORK/bin" "$WORK/repo/projA" "$WORK/repo/projB"
	git init -q "$WORK/repo"
	printf '[project]\nname = "a"\n' >"$WORK/repo/projA/pyproject.toml"
	printf 'x = 1\n' >"$WORK/repo/projA/mod.py"
	printf '[project]\nname = "b"\n' >"$WORK/repo/projB/pyproject.toml"
	printf 'y = 2\n' >"$WORK/repo/projB/mod.py"
	cat >"$WORK/bin/basedpyright" <<STUB
#!/bin/sh
pwd >> '$WORK/invocations.log'
printf '%s' '{"summary":{"errors":0},"generalDiagnostics":[]}'
exit 0
STUB
	chmod +x "$WORK/bin/basedpyright"
	run env PATH="$WORK/bin:$PATH" sh -c "cd '$WORK/repo' && printf '%s' '{\"stop_hook_active\":false}' | sh '$REPO/plugins/python-lsp/scripts/python-gate.sh'"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
	[ "$(wc -l <"$WORK/invocations.log" | tr -d ' ')" -eq 2 ]
}
