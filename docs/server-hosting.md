# Hosting the dedicated server

The Linux server build runs on any x86_64 host with systemd. The host pulls the latest
`main` build from the public pre-release `main-latest`, so it stores no credentials and
needs no inbound port. Right now the server only starts and idles: there is no networking
until milestone M5.

## 1. Create the VM (Google Cloud)

Compute Engine, Create instance:

| Setting | Value |
| --- | --- |
| Machine type | `e2-micro` |
| Boot disk | Debian 13 or Ubuntu 24.04, standard persistent disk, 10 to 30 GB |
| Firewall | leave HTTP and HTTPS unticked |
| Region | see below |

Google's free allowance covers one `e2-micro` only in `us-east1`, `us-central1` or
`us-west1`; check the current terms at <https://cloud.google.com/free>. Any other region
is billed by the hour. The owner's current VM, `meltdown`, is in `me-west1` (Tel Aviv),
chosen for low latency from Israel and therefore billed.

A Google Cloud budget only sends alerts. It does not stop spending.

## 2. Install

Open an SSH session on the VM and run:

```sh
curl -fsSLO https://raw.githubusercontent.com/noless-zz/meltdown/main/tools/install_server.sh
sudo bash install_server.sh
```

The script creates an unprivileged `meltdown` user, puts the binary in `/opt/meltdown/`,
verifies its checksum, and starts the `meltdown-server` service. It also installs a timer
that repeats the check every hour, so each merge to `main` reaches the host within about
an hour with no further action. Running the script again by hand is safe.

## 3. Check it

```sh
systemctl status meltdown-server          # should say "active (running)"
journalctl -u meltdown-server -n 50       # server log
systemctl list-timers meltdown-server-update.timer
journalctl -u meltdown-server-update -n 20
sudo systemctl start meltdown-server-update   # update now instead of waiting
```

The log shows OpenXR loader errors at start. They are expected on a machine with no
headset runtime; the line to look for is `Meltdown: running flat (no OpenXR session)`.

## Remove

```sh
sudo systemctl disable --now meltdown-server meltdown-server-update.timer
sudo rm -rf /opt/meltdown /var/lib/meltdown /usr/local/sbin/meltdown-server-update \
  /etc/systemd/system/meltdown-server*
sudo systemctl daemon-reload
sudo userdel meltdown
```
