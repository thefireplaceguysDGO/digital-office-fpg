#!/usr/bin/env python3
"""scripts/fpg-door.py — stdin/stdout <-> FPG's door, for ssh's ProxyCommand.

FPG_VPS1_DOOR is a `wss://computers.fpg.digital-office.co.il/share/<token>` address: the computers
app's share door, which carries SSH (OpenSSH on vps1) over a WebSocket. COMPUTERS_SHARE_KEY is the
ed25519 key that logs in as root. See CLAUDE.md § "This repository is the FPG office".

    ssh -o ProxyCommand="python3 scripts/fpg-door.py" -i ~/.ssh/fpg_share root@fpg-vps1

Needs `websockets` (pip install websockets). Trusts the cloud proxy's CA when it is present.
"""
import asyncio
import os
import ssl
import sys

import websockets

CA = "/root/.ccr/ca-bundle.crt"


async def main():
    ctx = ssl.create_default_context(cafile=CA if os.path.exists(CA) else None)
    async with websockets.connect(os.environ["FPG_VPS1_DOOR"], ssl=ctx, open_timeout=20,
                                  max_size=None, ping_interval=20) as ws:
        loop = asyncio.get_running_loop()
        reader = asyncio.StreamReader()
        await loop.connect_read_pipe(lambda: asyncio.StreamReaderProtocol(reader), sys.stdin.buffer)

        async def up():
            while (chunk := await reader.read(65536)):
                await ws.send(chunk)
            await ws.close()

        async def down():
            async for msg in ws:
                sys.stdout.buffer.write(msg if isinstance(msg, bytes) else msg.encode())
                sys.stdout.buffer.flush()

        await asyncio.wait([asyncio.create_task(up()), asyncio.create_task(down())],
                           return_when=asyncio.FIRST_COMPLETED)


asyncio.run(main())
