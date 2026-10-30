#!/bin/bash
# SessionStart (cloud sessions only) — the FPG office's «קדימה», done before the agent reads anything:
#   1. the door to FPG: ssh + websockets, the key from COMPUTERS_SHARE_KEY, `ssh fpg` through
#      FPG_VPS1_DOOR (scripts/fpg-door.py is the ProxyCommand)
#   2. the office: `./bbox run` started in the background when it is not already up or running
#   3. FPG is asked to answer, and the agent is told what it found and what «קדימה» means
# What it prints on stdout is the agent's context at the start of the session (see CLAUDE.md).
set -uo pipefail

[ "${CLAUDE_CODE_REMOTE:-}" = "true" ] || exit 0
cd "${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}" || exit 0
REPO="$PWD"
SOURCE="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("source",""))' 2>/dev/null || true)"
LOG="${TMPDIR:-/tmp}/bbox-run.log"
notes=()

# ── 1. the door ─────────────────────────────────────────────────────────────────────────────────
command -v ssh >/dev/null 2>&1 \
  || { apt-get install -y -qq openssh-client >/dev/null 2>&1 \
       || { apt-get update -qq >/dev/null 2>&1 && apt-get install -y -qq openssh-client >/dev/null 2>&1; }; } \
  || notes+=("openssh-client could not be installed")
python3 -c 'import websockets' 2>/dev/null \
  || pip install -q websockets >/dev/null 2>&1 \
  || notes+=("python websockets could not be installed")

fpg="not configured: FPG_VPS1_DOOR or COMPUTERS_SHARE_KEY is missing from the environment"
if [ -n "${FPG_VPS1_DOOR:-}" ] && [ -n "${COMPUTERS_SHARE_KEY:-}" ]; then
  (umask 077; mkdir -p ~/.ssh; printf '%s\n' "${COMPUTERS_SHARE_KEY}" > ~/.ssh/fpg_share)
  cat > ~/.ssh/fpg.conf <<EOF
Host fpg
  HostName fpg-vps1
  User root
  IdentityFile ~/.ssh/fpg_share
  IdentitiesOnly yes
  UserKnownHostsFile ~/.ssh/known_hosts_fpg
  StrictHostKeyChecking accept-new
  BatchMode yes
  ProxyCommand python3 ${REPO}/scripts/fpg-door.py
  ServerAliveInterval 20
  ControlMaster auto
  ControlPath ~/.ssh/cm-%r@%h
  ControlPersist 30m
EOF
  touch ~/.ssh/config && chmod 600 ~/.ssh/config ~/.ssh/fpg.conf
  grep -qxF 'Include ~/.ssh/fpg.conf' ~/.ssh/config \
    || { printf 'Include ~/.ssh/fpg.conf\n\n' | cat - ~/.ssh/config > ~/.ssh/config.new && mv ~/.ssh/config.new ~/.ssh/config; }
  if head="$(timeout 60 ssh fpg 'cd /opt/digital-office/fireplace && git log --oneline -1' 2>&1)"; then
    fpg="connected — \`ssh fpg\` is root on vps1; /opt/digital-office/fireplace is at: ${head}"
  else
    fpg="configured, but vps1 did not answer: ${head##*$'\n'}"
  fi
fi

# ── 2. the office ───────────────────────────────────────────────────────────────────────────────
office="already running (\`./bbox status\`)"
if pgrep -f 'bbox run' >/dev/null 2>&1; then
  office="\`./bbox run\` is already in progress — log: ${LOG}"
elif [ -z "$(DOCKER_HOST=unix:///run/bbox-docker.sock docker ps -q 2>/dev/null)" ]; then
  setsid nohup ./bbox run >"${LOG}" 2>&1 </dev/null &
  office="\`./bbox run\` started in the background (first bring-up ~15–25 min) — log: ${LOG}"
fi

# ── 3. what the agent is told ───────────────────────────────────────────────────────────────────
ctx="FPG office session (SessionStart hook, source=${SOURCE:-?}).
- FPG: ${fpg}
- This office: ${office}
${notes:+- Problems: ${notes[*]}
}«קדימה» from the owner — or a session with no task — means: do not ask what to do. Watch the
bring-up (read the log), take the next open item from FPG's Plane (\`ssh fpg 'cd
/opt/digital-office/fireplace && ./bbox project-pln tasks list'\`, urgent and in-progress first)
and carry it to its end under AGENTS.md. vps1 is production: read first, back up before anything
destructive, never touch files another session left uncommitted there."
python3 -c 'import json,sys; print(json.dumps({"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": sys.argv[1]}}, ensure_ascii=False))' "$ctx"
exit 0
