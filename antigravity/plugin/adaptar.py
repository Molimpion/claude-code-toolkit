import json
import os
import subprocess
import sys

CLAUDE = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.join(os.path.expanduser("~"), ".claude")
FILTRO_DE_PROMPT = [sys.executable, os.path.join(CLAUDE, "hooks", "block-secrets-in-prompt.py")]
TRAVA_DO_ENV = ["node", os.path.join(CLAUDE, "hooks", "bloquear-env.mjs")]
LOG_DE_ESCRITA = [sys.executable, os.path.join(CLAUDE, "hooks", "log-writes.py")]
HOOKS_DA_MEMORIA = os.path.join(CLAUDE, "ai-memory", "hooks", "antigravity-cli")

FERRAMENTA_DO_CLAUDE = {
    "read_file": ("Read", "file_path", "Path"),
    "write_file": ("Write", "file_path", "Path"),
    "edit_file": ("Edit", "file_path", "Path"),
    "run_command": ("Bash", "command", "CommandLine"),
}
FERRAMENTAS_DE_ESCRITA = {"write_file", "edit_file"}


def rodar(comando, entrada):
    return subprocess.run(comando, input=json.dumps(entrada), capture_output=True, text=True)


def filtrar_prompt(payload):
    return rodar(FILTRO_DE_PROMPT, {"prompt": payload.get("lastUserInput", "")})


def repassar_a_memoria(script, payload, prompt_limpo):
    caminho = os.path.join(HOOKS_DA_MEMORIA, script + ".sh")
    if not prompt_limpo or not os.path.isfile(caminho):
        return ""
    return subprocess.run(
        ["sh", caminho], input=json.dumps(payload), capture_output=True, text=True, timeout=10
    ).stdout


def chamada_no_formato_do_claude(payload):
    chamada = payload.get("toolCall") or {}
    nome = chamada.get("name", "")
    argumentos = chamada.get("args") or {}
    if nome in FERRAMENTA_DO_CLAUDE:
        ferramenta, campo, origem = FERRAMENTA_DO_CLAUDE[nome]
        return {"tool_name": ferramenta, "tool_input": {campo: argumentos.get(origem, "")}}
    textos = " ".join(valor for valor in argumentos.values() if isinstance(valor, str))
    return {"tool_name": "Bash", "tool_input": {"command": textos}}


def pre_invocation(payload):
    filtro = filtrar_prompt(payload)
    if filtro.returncode == 2:
        return {
            "injectSteps": [{"errorMessage": {"userMessage": filtro.stderr.strip()}}],
            "terminationBehavior": "terminate",
        }
    saida = repassar_a_memoria("session-start", payload, filtro.returncode == 0).strip()
    return json.loads(saida) if saida else {}


def pre_tool_use(payload):
    trava = rodar(TRAVA_DO_ENV, chamada_no_formato_do_claude(payload))
    repassar_a_memoria("pre-tool-use", payload, filtrar_prompt(payload).returncode == 0)
    if trava.returncode == 2:
        return {"decision": "deny", "reason": trava.stderr.strip()}
    return {"decision": "ask"}


def post_tool_use(payload):
    chamada = payload.get("toolCall") or {}
    nome = chamada.get("name", "")
    if nome in FERRAMENTAS_DE_ESCRITA:
        caminho = (chamada.get("args") or {}).get("Path", "?")
        rodar(LOG_DE_ESCRITA, {"tool_name": "agy:" + nome, "tool_input": {"file_path": caminho}})
    repassar_a_memoria("post-tool-use", payload, filtrar_prompt(payload).returncode == 0)
    return {}


def stop(payload):
    repassar_a_memoria("stop", payload, filtrar_prompt(payload).returncode == 0)
    return {"decision": ""}


EVENTOS = {
    "pre-invocation": pre_invocation,
    "pre-tool-use": pre_tool_use,
    "post-tool-use": post_tool_use,
    "stop": stop,
}

evento = sys.argv[1]
try:
    payload = json.load(sys.stdin)
except ValueError:
    if evento == "pre-tool-use":
        print(json.dumps({"decision": "deny", "reason": "O hook do toolkit não conseguiu ler o pedido da ferramenta e o recusou por segurança."}))
    else:
        print("{}")
    sys.exit(0)

print(json.dumps(EVENTOS[evento](payload), ensure_ascii=False))
