#!/usr/bin/env python3
"""A private key as it arrives from a secret store (stdin) → a well-formed OpenSSH/PEM file (stdout).

Secret stores flatten newlines — to spaces, or to a literal `\\n` — and ssh refuses a key whose
body is not split into lines. The armour lines are kept, the body is re-split on whitespace.
"""
import re
import sys

s = sys.stdin.read().replace("\\n", "\n").strip()
m = re.match(r"(-----BEGIN [A-Z ]+-----)(.*?)(-----END [A-Z ]+-----)", s, re.S)
print(m.group(1) + "\n" + "\n".join(m.group(2).split()) + "\n" + m.group(3) if m else s)
