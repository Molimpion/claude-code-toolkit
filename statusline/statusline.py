import json
import sys


def tokens(n):
    if n >= 1_000_000:
        return f"{n / 1_000_000:g}M"
    if n >= 1_000:
        return f"{round(n / 1_000)}k"
    return str(n)


dados = json.load(sys.stdin)
partes = [dados.get("model", {}).get("display_name", "?")]

contexto = dados.get("context_window") or {}
uso = contexto.get("current_usage") or {}
total = contexto.get("context_window_size")
if uso and total:
    usado = (
        uso.get("input_tokens", 0)
        + uso.get("cache_creation_input_tokens", 0)
        + uso.get("cache_read_input_tokens", 0)
    )
    partes.append(f"contexto {tokens(usado)}/{tokens(total)} ({contexto.get('used_percentage', round(100 * usado / total))}%)")

limites = dados.get("rate_limits") or {}
for chave, rotulo in (("five_hour", "5h"), ("seven_day", "7d")):
    janela = limites.get(chave)
    if janela and janela.get("used_percentage") is not None:
        partes.append(f"{rotulo} {janela['used_percentage']}%")

print(" · ".join(partes))
