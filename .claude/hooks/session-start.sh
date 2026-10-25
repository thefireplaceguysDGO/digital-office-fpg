#!/bin/bash
# A Claude cloud session IS the cloud office (ai/context/fpg-herd.md): bring it up and attach vps1,
# with no instruction from anyone. Both halves come from the environment's secrets:
#   FPG_VPS1_DOOR        the door vps1 printed (./bbox computers share local … on vps1)
#   COMPUTERS_SHARE_KEY  the private key whose public half vps1 shared to
# Missing either, or not a cloud session → nothing happens. The work runs DETACHED (a first
# bring-up builds images for ~10–15 min) and logs to /tmp/claude-cloud-office.log; the session
# does not wait for it.
set -uo pipefail
[ "${CLAUDE_CODE_REMOTE:-}" = "true" ] || exit 0
[ -n "${FPG_VPS1_DOOR:-}" ] && [ -n "${COMPUTERS_SHARE_KEY:-}" ] || exit 0
cd "${CLAUDE_PROJECT_DIR:-$(dirname "$0")/../..}" || exit 0
LOG=/tmp/claude-cloud-office.log

nohup setsid bash -c '
  set -uo pipefail
  say() { echo "[$(date -u +%H:%M:%S)] $*"; }
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
  ./bbox computers ssh vps1 "hostname; uptime" </dev/null && say "OK — the cloud office reaches vps1"
' > "${LOG}" 2>&1 < /dev/null &

echo "cloud office: bringing up and attaching vps1 in the background — tail -f ${LOG}"
