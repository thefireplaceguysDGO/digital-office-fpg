# The FPG herd — vps1 and the Claude cloud office

| Office | Where | What it runs | Role |
|---|---|---|---|
| **vps1** | the VPS, `https://console.fpg.digital-office.co.il` | every app | the main office: production, the data, the users |
| **claude-cloud** | a Claude Code cloud session (this checkout, `./bbox run`) | the chassis only: traefik, postgres, redis, authentik, connections, console, app-management, computers, dgo-extend | the access point: operate vps1, develop and test changes, update vps1 |

## How the cloud office reaches vps1

A cloud session's egress is an HTTPS proxy that re-terminates TLS (measured 2026-10-25): only 80/443
leave the sandbox, so SSH (22) and dgo-extend's WireGuard link (UDP) never arrive. WebSockets do. So
vps1 **shares its computer** with the cloud office — a feature of `computers`
([AGENT.md](../../apps/computers/AGENT.md) § Sharing): a `wss://computers.fpg.digital-office.co.il/share/<token>`
door relayed to vps1's own sshd, opened by the token and authenticated by sshd's key check.

The sandbox does not outlive its session, so its identity comes from two environment secrets:

| Secret | What |
|---|---|
| `COMPUTERS_SHARE_KEY` | the cloud office's durable private key (its public half is what vps1 shares to) |
| `FPG_VPS1_DOOR` | the door vps1 printed when it shared |

## Once, on vps1 (as root, in its checkout, with this branch's `computers` merged)

```bash
./bbox update computers                                          # the image with `shares`
./bbox computers share local "<public half of COMPUTERS_SHARE_KEY>" claude-cloud   # prints the door ONCE
```

`local` is vps1's built-in machine; its office key must already be approved there
(`GET /api/office-key` → `authorize_command`) — the share is installed through that access. Any other
machine vps1 owns is shared the same way by its id. Revoke: `./bbox computers share revoke <share-id>`.

## Every cloud session

```bash
./bbox run
./bbox computers share attach "$FPG_VPS1_DOOR" root vps1          # vps1 joins this office's fleet
./bbox computers ssh <vps1-id> 'cd <checkout> && ./bbox status'   # or no command: a shell
```

Then `/api/computers/<id>/exec` and `/stream` work on vps1 as on any machine of the fleet.
