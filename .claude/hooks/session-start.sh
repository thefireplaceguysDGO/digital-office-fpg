#!/bin/bash
# A Claude cloud session IS the cloud office (ai/context/fpg-herd.md): bring it up and attach vps1,
# with no instruction from anyone. Both halves come from the environment's secrets:
#   FPG_VPS1_DOOR        the door vps1 printed (./bbox computers share local … on vps1)
#   COMPUTERS_SHARE_KEY  the private key whose public half vps1 shared to
# Missing either, or not a cloud session → nothing happens. Two paths, both logged to
# /tmp/claude-cloud-office.log:
#   1. FAST, in seconds, before the session starts: ssh to vps1 straight through its door
#      (`./bbox computers door`) — no docker, no stack — and `ssh vps1` works from then on;
#   2. FULL, detached, after it: the cloud office itself (a cold bring-up builds images for
#      ~10–15 min) with vps1 attached to its fleet. The session does not wait for it.
set -uo pipefail
[ "${CLAUDE_CODE_REMOTE:-}" = "true" ] || exit 0
[ -n "${FPG_VPS1_DOOR:-}" ] && [ -n "${COMPUTERS_SHARE_KEY:-}" ] || exit 0
cd "${CLAUDE_PROJECT_DIR:-$(dirname "$0")/../..}" || exit 0
LOG=/tmp/claude-cloud-office.log
say() { echo "[$(date -u +%H:%M:%S)] $*"; }

t0=$(date +%s)
if out="$(timeout 60 ./bbox computers door vps1 'hostname; uptime' </dev/null 2>&1)"; then
  line="FAST — vps1 answered through its door in $(( $(date +%s) - t0 ))s: $(echo "${out}" | grep -v '^Warning' | tr -s ' \n' ' ' | sed 's/ $//')"
else
  line="FAST — vps1 did NOT answer through its door ($(echo "${out}" | tail -1))"
fi
say "${line}" | tee -a "${LOG}"

nohup setsid bash -c '
  set -uo pipefail
  say() { echo "[$(date -u +%H:%M:%S)] $*"; }
  # one bring-up at a time: a resumed session fires this hook again while the last one still runs
  exec 9>/tmp/claude-cloud-office.lock
  flock -n 9 || { say "FULL — a bring-up is already running; not starting another"; exit 0; }
  # bbox gives up if dockerd is slow to answer on a cold sandbox; the second run finds it up
  for i in 1 2; do ./bbox run && break; say "bbox run exited $? (attempt $i)"; done
  export DOCKER_HOST=unix:///run/bbox-docker.sock
  for i in $(seq 300); do
    docker ps --format "{{.Names}} {{.Status}}" 2>/dev/null | grep -qE "^computers-.*\(healthy\)" && break
    sleep 3
  done
  if ./bbox computers ssh list 2>/dev/null | grep -qE "[[:space:]]vps1[[:space:]]"; then
    say "vps1 already in the fleet"
  else
    ./bbox computers share attach "$FPG_VPS1_DOOR" root vps1 >/dev/null && say "vps1 attached"
  fi
  ./bbox computers ssh vps1 "hostname; uptime" </dev/null && say "FULL — the cloud office reaches vps1"
' >> "${LOG}" 2>&1 < /dev/null &

echo "cloud office: \`ssh vps1\` is ready; the full office is coming up in the background — tail -f ${LOG}"
