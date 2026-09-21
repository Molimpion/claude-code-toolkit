#!/usr/bin/env python3
"""Hook PostToolUse: registra cada arquivo escrito ou editado pelo agente."""
import json
import os
import sys
import time

LOG = os.path.expanduser("~/.claude/arquivos-tocados.log")

data = json.load(sys.stdin)
tool = data.get("tool_name", "?")
path = data.get("tool_input", {}).get("file_path", "?")

with open(LOG, "a") as f:
    f.write(f"{time.strftime('%Y-%m-%d %H:%M')} {tool} {path}\n")
