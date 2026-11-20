#!/usr/bin/env bash
# Runs the game against Monado with a simulated headset and two simulated
# controllers, and checks that an OpenXR session with two views came up
# (issue #26, PLT-2) and that both hands tracked (issue #571, PLT-5). Also
# reports how often XR_ERROR_SESSION_NOT_STOPPING was logged (issue #575).
#
# Usage: tools/xr_smoke.sh [frames]
# XR_SMOKE_TIMEOUT: seconds Godot may take for the whole run (default 300).
# XR_SMOKE_SOCKET_WAIT: seconds to wait for Monado's socket (default 30).
#
# Prints one MELTDOWN_XR_SMOKE_TIMES line with how long each phase took,
# also when the run fails, so a slow or stuck phase shows in the log
# (issue #727). The times come from this script's clock, read when a phase's
# marker line first appears in the Godot log; null means the phase never ended.
# Needs: godot, monado-service, xvfb-run, python3 and a software Vulkan driver
# (lavapipe).
# Logs are left in build/xr-smoke/ for CI to upload.
set -euo pipefail

frames="${1:-120}"
budget="${XR_SMOKE_TIMEOUT:-300}"
socket_wait="${XR_SMOKE_SOCKET_WAIT:-30}"
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
# Simulated controllers for both hands (issue #559). Monado 25 reads
# SIMULATED_ENABLE, SIMULATED_LEFT and SIMULATED_RIGHT. Of the hand values,
# simple, wmr and ml2 were tried and all create two controllers; "simple"
# offers /interaction_profiles/khr/simple_controller, which the game's action map
# binds (issue #571), so both hands must track; see the addenda in
# docs/decisions/0002-monado-in-ci.md.
export SIMULATED_ENABLE=1
export SIMULATED_LEFT="${SIMULATED_LEFT:-simple}"
export SIMULATED_RIGHT="${SIMULATED_RIGHT:-simple}"

now() { date +%s.%N; }
# Seconds between two clock readings, or null when either is missing.
span() {
	if [ -z "$1" ] || [ -z "$2" ]; then
		printf null
	else
		python3 -c 'import sys; print(round(float(sys.argv[2]) - float(sys.argv[1]), 1))' "$1" "$2"
	fi
}
t_monado=""; t_socket=""; t_godot=""; t_ready=""; t_session=""; t_first=""; t_last=""; t_exit=""
print_times() {
	echo "MELTDOWN_XR_SMOKE_TIMES {\"monado_socket_s\":$(span "$t_monado" "$t_socket"),\"godot_to_ready_s\":$(span "$t_godot" "$t_ready"),\"godot_to_session_s\":$(span "$t_godot" "$t_session"),\"session_to_first_frame_s\":$(span "$t_session" "$t_first"),\"first_frame_to_last_s\":$(span "$t_first" "$t_last"),\"godot_total_s\":$(span "$t_godot" "$t_exit"),\"budget_s\":$budget,\"frames\":$frames}"
}

# The service watches stdin for a quit key and fails to start when stdin is
# not pollable (as with /dev/null), so it is given a pipe that stays open.
rm -f "$XDG_RUNTIME_DIR/monado_comp_ipc" "$XDG_RUNTIME_DIR/monado.pid"
t_monado="$(now)"
sleep 1200 | monado-service > "$log_dir/monado.log" 2>&1 &
trap 'print_times; pkill -x monado-service || true; pkill -P $$ sleep || true' EXIT

# The socket usually appears within a second; a busy runner once took more
# than the old 10 s (issue #727), so the wait is generous.
deadline=$(( $(date +%s) + socket_wait ))
while [ ! -S "$XDG_RUNTIME_DIR/monado_comp_ipc" ] && [ "$(date +%s)" -lt "$deadline" ]; do
	sleep 0.2
done
if [ ! -S "$XDG_RUNTIME_DIR/monado_comp_ipc" ]; then
	echo "xr_smoke: monado-service did not open its socket within ${socket_wait} s" >&2
	tail -n 40 "$log_dir/monado.log" >&2
	exit 1
fi
t_socket="$(now)"

# One rasteriser thread. Mesa 26.0 lavapipe crashed (signal 11 in a worker
# thread) on the first CI run, which used four threads and the Forward+
# renderer in stereo; see docs/decisions/0002-monado-in-ci.md.
export LP_NUM_THREADS="${LP_NUM_THREADS:-1}"

# A real window is needed for the Vulkan renderer; --headless would select the
# dummy renderer and OpenXR could not create its swapchains. The renderer is
# named because --rendering-driver alone makes Godot pick Forward+ instead of
# the project's Mobile renderer, which is the one the Quest runs.
: > "$log_dir/godot.log"
t_godot="$(now)"
timeout "$budget" xvfb-run -a godot --path "$root/game" --rendering-driver vulkan --rendering-method mobile \
	-- "--xr-smoke-frames=$frames" > "$log_dir/godot.log" 2>&1 &
godot_pid=$!
# Watches the log for each phase's marker while Godot runs. Godot flushes
# every printed line, so a marker is seen within one poll of being printed.
seen() { grep -a -q -E "$1" "$log_dir/godot.log"; }
while kill -0 "$godot_pid" 2> /dev/null; do
	[ -z "$t_ready" ] && seen '^Meltdown: (OpenXR session active|running flat)' && t_ready="$(now)"
	[ -z "$t_session" ] && seen '^MELTDOWN_RENDER_MODELS .*"phase":"session"' && t_session="$(now)"
	[ -z "$t_first" ] && seen '^MELTDOWN_XR_SMOKE_FRAME \{"frame":1,' && t_first="$(now)"
	[ -z "$t_last" ] && seen '^MELTDOWN_XR_SMOKE ' && t_last="$(now)"
	sleep 0.2
done
set +e
wait "$godot_pid"
status=$?
set -e
t_exit="$(now)"
# A marker printed in the last poll interval is only seen now.
[ -z "$t_ready" ] && seen '^Meltdown: (OpenXR session active|running flat)' && t_ready="$t_exit"
[ -z "$t_session" ] && seen '^MELTDOWN_RENDER_MODELS .*"phase":"session"' && t_session="$t_exit"
[ -z "$t_first" ] && seen '^MELTDOWN_XR_SMOKE_FRAME \{"frame":1,' && t_first="$t_exit"
[ -z "$t_last" ] && seen '^MELTDOWN_XR_SMOKE ' && t_last="$t_exit"
if [ "$status" -eq 124 ]; then
	echo "xr_smoke: godot did not finish within the ${budget} s budget (XR_SMOKE_TIMEOUT)" >&2
fi

line="$(grep -a '^MELTDOWN_XR_SMOKE ' "$log_dir/godot.log" | tail -n 1 || true)"
if [ -z "$line" ]; then
	echo "xr_smoke: no result line (godot exit code $status)" >&2
	tail -n 60 "$log_dir/godot.log" >&2
	exit 1
fi
echo "$line"
echo "$line" > "$log_dir/result.txt"
# Reported, never a failure: Godot 4.7.2 cannot end the session before
# quitting (#558), so the count shows whether a later fix removes the error
# (issue #575, decision record 0002, limit 5).
not_stopping="$("$root/tools/count_session_not_stopping.sh" "$log_dir/godot.log")"
echo "MELTDOWN_XR_SMOKE_SHUTDOWN {\"session_not_stopping_errors\":$not_stopping}"

json="${line#MELTDOWN_XR_SMOKE }"
session="$(printf '%s' "$json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["session"])')"
views="$(printf '%s' "$json" | python3 -c 'import json,sys; print(int(json.load(sys.stdin)["views"]))')"
left="$(printf '%s' "$json" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("left_tracked") is True)')"
right="$(printf '%s' "$json" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("right_tracked") is True)')"
echo "xr_smoke: simulated controllers left_tracked=$left right_tracked=$right"
if [ "$session" != "True" ] || [ "$views" -lt 2 ]; then
	echo "xr_smoke: no OpenXR session with two views (session=$session views=$views)" >&2
	exit 1
fi
# Each hand is named so a failure says which one lost its binding (issue #571).
untracked=0
for hand in left right; do
	value="$left"
	[ "$hand" = right ] && value="$right"
	if [ "$value" != "True" ]; then
		echo "xr_smoke: the $hand hand never tracked (${hand}_tracked=false)" >&2
		untracked=1
	fi
done
if [ "$untracked" -ne 0 ]; then
	exit 1
fi
if [ "$status" -ne 0 ]; then
	echo "xr_smoke: godot exited with code $status after reporting a session" >&2
	exit 1
fi
echo "xr_smoke: OpenXR session with $views views"
