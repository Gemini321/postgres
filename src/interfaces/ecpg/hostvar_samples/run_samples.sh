#!/usr/bin/env bash
set -euo pipefail

if ! command -v ecpg >/dev/null 2>&1; then
	export PATH=/home/oracle/pgsql/bin:$PATH
fi
ROOT_DIR=$(cd "$(dirname "$0")" && pwd)
cd "$ROOT_DIR"

# remove stale generated artifacts before compiling new ones
# find . -name '*.c' -o -name '*.bin' | xargs -r rm -f

if [[ $# -gt 0 ]]; then
	mapfile -t SAMPLES < <(printf '%s\n' "$@")
else
	mapfile -t SAMPLES < <(find . -name '*.pgc' | sort)
fi

if [[ ${#SAMPLES[@]} -eq 0 ]]; then
	echo "No .pgc files found." >&2
	exit 1
fi

INCLUDEDIR=$(pg_config --includedir)
LIBDIR=$(pg_config --libdir)
export LD_LIBRARY_PATH="$LIBDIR:${LD_LIBRARY_PATH-}"

for sample in "${SAMPLES[@]}"; do
	sample=${sample#./}
	base=${sample%.pgc}
	c_file="${base}.c"
	bin_file="${base}.bin"

	rm -f "$c_file" "$bin_file"
	echo "[ECPG] $sample"
	ecpg -o "$c_file" "$sample"
	echo "[CC]   $c_file -> $bin_file"
	gcc "$c_file" -I"$INCLUDEDIR" -L"$LIBDIR" -lecpg -lpq -o "$bin_file"
	echo "Built $bin_file (run manually to exercise runtime behavior)."
	./"$bin_file"
	echo
done
