#!/usr/bin/env python3
"""Hook UserPromptSubmit: bloqueia o envio de prompts que contenham segredos."""
import json
import re
import sys

PATTERNS = {
    "token do GitHub": r"\b(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{30,}|\bgithub_pat_[A-Za-z0-9_]{40,}",
    "chave da Anthropic": r"\bsk-ant-[A-Za-z0-9_-]{20,}",
    "chave da OpenAI": r"\bsk-(proj-)?[A-Za-z0-9_-]{32,}",
    "chave da Groq": r"\bgsk_[A-Za-z0-9]{40,}",
    "chave de acesso da AWS": r"\bAKIA[0-9A-Z]{16}\b",
    "chave do SendGrid": r"\bSG\.[A-Za-z0-9_-]{16,}\.[A-Za-z0-9_-]{16,}",
    "token do Slack": r"\bxox[abprs]-[A-Za-z0-9-]{10,}",
    "chave privada": r"-----BEGIN [A-Z ]*PRIVATE KEY-----",
    "URL de banco com senha": r"\b(postgres(ql)?|mysql|mongodb(\+srv)?|redis)://[^\s:@/]+:[^\s@/]+@",
}

prompt = json.load(sys.stdin).get("prompt", "")
found = [name for name, rx in PATTERNS.items() if re.search(rx, prompt)]

if found:
    print(
        "Prompt bloqueado: parece conter " + ", ".join(found) + ". "
        "Remova o valor e descreva o que precisa sem colar o segredo.",
        file=sys.stderr,
    )
    sys.exit(2)
