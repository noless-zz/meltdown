#!/usr/bin/env bash
# Runs the game against Monado with a simulated headset and checks that an
# OpenXR session with two views came up (issue #26, PLT-2).
#
# Usage: tools/xr_smoke.sh [frames]
# Needs: godot, monado-service, xvfb-run, python3 and a software Vulkan driver
# (lavapipe).
# Logs are left in build/xr-smoke/ for CI to upload.
set -euo pipefail

frames="${1:-120}"
root="$(cd "$(dirname "$0")/.." && pwd)"
log_dir="$root/build/xr-smoke"
mkdir -p "$log_dir"

# Monado puts its socket in XDG_RUNTIME_DIR; CI runners have none set.
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-$(mktemp -d)}"
chmod 700 "$XDG_RUNTIME_DIR"
# The packaged runtime manifest; set explicitly so the result does not depend
# on which runtime the machine has registered as active.
export XR_RUNTIME_JSON="${XR_RUNTIME_JSON:-/usr/share/openxr/1/openxr_monado.json}"
# The null compositor shows nothing and needs no display or GPU. With no
# headset attached Monado creates its "Simulated HMD" by itself.
export XRT_COMPOSITOR_NULL=1
export XRT_LOG="${XRT_LOG:-info}"

# The service watches stdin for a quit key and fails to start when stdin is
# not pollable (as with /dev/null), so it is given a pipe that stays open.
rm -f "$XDG_RUNTIME_DIR/monado_comp_ipc" "$XDG_RUNTIME_DIR/monado.pid"
sleep 600 | monado-service > "$log_dir/monado.log" 2>&1 &
trap 'pkill -x monado-service || true; pkill -P $$ sleep || true' EXIT

for _ in $(seq 1 50); do
	[ -S "$XDG_RUNTIME_DIR/monado_comp_ipc" ] && break
	sleep 0.2
done
if [ ! -S "$XDG_RUNTIME_DIR/monado_comp_ipc" ]; then
	echo "xr_smoke: monado-service did not open its socket" >&2
	tail -n 40 "$log_dir/monado.log" >&2
	exit 1
fi

# One rasteriser thread. Mesa 26.0 lavapipe crashed (signal 11 in a worker
# thread) on the first CI run, which used four threads and the Forward+
# renderer in stereo; see docs/decisions/0002-monado-in-ci.md.
export LP_NUM_THREADS="${LP_NUM_THREADS:-1}"

# A real window is needed for the Vulkan renderer; --headless would select the
# dummy renderer and OpenXR could not create its swapchains. The renderer is
# named because --rendering-driver alone makes Godot pick Forward+ instead of
# the project's Mobile renderer, which is the one the Quest runs.
set +e
timeout 120 xvfb-run -a godot --path "$root/game" --rendering-driver vulkan --rendering-method mobile \
	-- "--xr-smoke-frames=$frames" > "$log_dir/godot.log" 2>&1
status=$?
set -e

line="$(grep -a '^MELTDOWN_XR_SMOKE ' "$log_dir/godot.log" | tail -n 1 || true)"
if [ -z "$line" ]; then
	echo "xr_smoke: no result line (godot exit code $status)" >&2
	tail -n 60 "$log_dir/godot.log" >&2
	exit 1
fi
echo "$line"
echo "$line" > "$log_dir/result.txt"

json="${line#MELTDOWN_XR_SMOKE }"
session="$(printf '%s' "$json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["session"])')"
views="$(printf '%s' "$json" | python3 -c 'import json,sys; print(int(json.load(sys.stdin)["views"]))')"
if [ "$session" != "True" ] || [ "$views" -lt 2 ]; then
	echo "xr_smoke: no OpenXR session with two views (session=$session views=$views)" >&2
	exit 1
fi
if [ "$status" -ne 0 ]; then
	echo "xr_smoke: godot exited with code $status after reporting a session" >&2
	exit 1
fi
echo "xr_smoke: OpenXR session with $views views"
