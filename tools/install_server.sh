#!/usr/bin/env bash
# Installs or updates the Meltdown dedicated server on a Linux host (MP-3).
#
# Usage, as root on Debian 13 or Ubuntu 24.04 (x86_64):
#   curl -fsSLO https://raw.githubusercontent.com/noless-zz/meltdown/main/tools/install_server.sh
#   sudo bash install_server.sh
#
# The host pulls the latest `main` build from the public rolling release, so
# it holds no token or key (DEV-10) and needs no inbound port. Running the
# script again is safe: it only replaces the binary and restarts the service
# when the published checksum has changed. A systemd timer does that hourly.
set -euo pipefail

# Overridable so the script can be tested against a local directory
# (file:///...) without a published release.
release_url="${MELTDOWN_RELEASE_URL:-https://github.com/noless-zz/meltdown/releases/download/main-latest}"

binary_name="meltdown-server.x86_64"
install_dir="/opt/meltdown"
updater="/usr/local/sbin/meltdown-server-update"
unit_dir="/etc/systemd/system"
service_user="meltdown"

if [ "$(id -u)" -ne 0 ]; then
	echo "Run as root: sudo bash $0" >&2
	exit 1
fi
if [ "$(uname -m)" != "x86_64" ]; then
	echo "Only x86_64 builds are published; this host is $(uname -m)" >&2
	exit 1
fi
self="${BASH_SOURCE[0]:-}"
if [ ! -f "$self" ]; then
	# The hourly timer runs a saved copy of this script, so it must be a file.
	echo "Download the script to a file first; do not pipe it into bash" >&2
	exit 1
fi
for tool in curl sha256sum systemctl; do
	if ! command -v "$tool" > /dev/null; then
		echo "Missing required tool: $tool" >&2
		exit 1
	fi
done

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# write_if_changed <destination> <mode>: installs stdin at the destination and
# returns 0 only when the content differed, so callers know whether to reload.
write_if_changed() {
	local dest="$1" mode="$2" staged="$work/staged"
	cat > "$staged"
	if [ -f "$dest" ] && cmp -s "$staged" "$dest"; then
		return 1
	fi
	install -m "$mode" "$staged" "$dest"
	return 0
}

# The service never runs as root. Its home is the state directory systemd
# creates, the only place it may write.
if ! id "$service_user" > /dev/null 2>&1; then
	useradd --system --home-dir /var/lib/meltdown --no-create-home \
		--shell /usr/sbin/nologin "$service_user"
fi
# Owned by root so a compromised server process cannot replace its own binary.
install -d -m 0755 "$install_dir"

# The checksum file doubles as the version marker. It comes from the same
# release as the binary, so it guards against a partial or mixed download,
# not against a compromised release.
binary_changed=0
curl -fsSL -o "$work/$binary_name.sha256" "$release_url/$binary_name.sha256"
if [ ! -x "$install_dir/$binary_name" ] \
		|| ! cmp -s "$work/$binary_name.sha256" "$install_dir/$binary_name.sha256"; then
	curl -fsSL -o "$work/$binary_name" "$release_url/$binary_name"
	(cd "$work" && sha256sum --check --quiet "$binary_name.sha256")
	# Rename into place: a running server keeps its old file until restarted,
	# and an interrupted update never leaves a half-written binary.
	install -m 0755 "$work/$binary_name" "$install_dir/$binary_name.new"
	mv -f "$install_dir/$binary_name.new" "$install_dir/$binary_name"
	install -m 0644 "$work/$binary_name.sha256" "$install_dir/$binary_name.sha256"
	binary_changed=1
fi

if [ "$(readlink -f "$self")" != "$updater" ]; then
	install -m 0755 "$self" "$updater"
fi

units_changed=0
service_changed=0
if write_if_changed "$unit_dir/meltdown-server.service" 0644 <<UNIT
[Unit]
Description=Meltdown dedicated server
After=network-online.target
Wants=network-online.target

[Service]
User=$service_user
Group=$service_user
StateDirectory=meltdown
WorkingDirectory=/var/lib/meltdown
Environment=HOME=/var/lib/meltdown
ExecStart=$install_dir/$binary_name --headless
Restart=on-failure
RestartSec=5
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
UNIT
then
	units_changed=1
	service_changed=1
fi
if write_if_changed "$unit_dir/meltdown-server-update.service" 0644 <<UNIT
[Unit]
Description=Update the Meltdown dedicated server
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$updater
UNIT
then
	units_changed=1
fi
if write_if_changed "$unit_dir/meltdown-server-update.timer" 0644 <<UNIT
[Unit]
Description=Check hourly for a new Meltdown server build

[Timer]
OnBootSec=5min
OnUnitActiveSec=1h
RandomizedDelaySec=5min

[Install]
WantedBy=timers.target
UNIT
then
	units_changed=1
fi

if [ "$units_changed" -eq 1 ]; then
	systemctl daemon-reload
fi
systemctl enable --quiet meltdown-server.service meltdown-server-update.timer
systemctl start meltdown-server-update.timer
if [ "$binary_changed" -eq 1 ] || [ "$service_changed" -eq 1 ]; then
	systemctl restart meltdown-server.service
	echo "Meltdown server updated to $(cut -c1-12 "$install_dir/$binary_name.sha256") and restarted"
else
	# Starts it if it was stopped; does nothing to a running server.
	systemctl start meltdown-server.service
	echo "Meltdown server already up to date"
fi
