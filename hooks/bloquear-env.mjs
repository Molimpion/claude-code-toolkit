import { readFileSync } from "node:fs";

const ARQUIVO_DE_SEGREDO = /(?<![\w.$-])\.env(?!\.example(?![\w.-]))(?![\w-])/i;

const CAMPOS_POR_FERRAMENTA = {
  Bash: ["command"],
  PowerShell: ["command"],
  Read: ["file_path"],
  Edit: ["file_path"],
  MultiEdit: ["file_path"],
  Write: ["file_path"],
  NotebookEdit: ["notebook_path"],
  Grep: ["path", "glob"],
  Glob: ["pattern", "path"],
};

function bloquear(motivo) {
  process.stderr.write(motivo);
  process.exit(2);
}

let pedido;
try {
  pedido = JSON.parse(readFileSync(0, "utf8"));
} catch {
  bloquear("A trava do .env não conseguiu ler o pedido da ferramenta e o recusou por segurança.");
}

const campos = CAMPOS_POR_FERRAMENTA[pedido.tool_name] ?? [];
const entrada = pedido.tool_input ?? {};
const alvo = campos.map((campo) => entrada[campo]).find(
  (valor) => typeof valor === "string" && ARQUIVO_DE_SEGREDO.test(valor),
);

if (alvo !== undefined) {
  bloquear(
    "Bloqueado: o .env guarda os segredos do projeto e o agente não lê nem edita esse arquivo. " +
      "Se falta uma variável, diga à pessoa qual é, consultando o .env.example. Se a intenção era " +
      "só buscar o texto \".env\" em código ou documentação, escreva o padrão da busca como [.]env.",
  );
}
