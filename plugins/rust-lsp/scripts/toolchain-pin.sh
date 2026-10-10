# Answers whether a directory sits under a rustup toolchain pin that is not installed.
# Reads the filesystem only: calling rustup here would download the pinned toolchain,
# about a gigabyte, with no prompt, inside a hook.
pinned_toolchain_missing() {
	rustup_home="${RUSTUP_HOME:-${HOME:-}/.rustup}"
	[ -d "$rustup_home/toolchains" ] || return 1
	pin_walk_dir="$1"
	while [ -n "$pin_walk_dir" ] && [ "$pin_walk_dir" != "/" ]; do
		for pin_file in rust-toolchain.toml rust-toolchain; do
			[ -f "$pin_walk_dir/$pin_file" ] || continue
			channel_name="$(grep -m1 -E '^[[:space:]]*channel[[:space:]]*=' "$pin_walk_dir/$pin_file" 2>/dev/null |
				sed -E 's/.*=[[:space:]]*"?([^"[:space:]]+)"?.*/\1/' || true)"
			if [ -z "$channel_name" ] && [ "$pin_file" = "rust-toolchain" ]; then
				channel_name="$(head -n1 "$pin_walk_dir/$pin_file" 2>/dev/null | tr -d '[:space:]')"
			fi
			# a pin this helper cannot read is treated as missing: skip rather than risk a download
			[ -n "$channel_name" ] || return 0
			for toolchain_dir in "$rustup_home/toolchains/$channel_name" "$rustup_home/toolchains/$channel_name"-*; do
				[ -d "$toolchain_dir" ] && return 1
			done
			return 0
		done
		pin_walk_dir="$(dirname -- "$pin_walk_dir")"
	done
	return 1
}
