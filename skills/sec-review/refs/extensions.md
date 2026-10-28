# Extensões: hooks, plugins, ferramentas MCP

Carregar no **Step 0** só quando o repositório executa código de terceiro ou é
executado por outro sistema como extensão. Entra na cobertura do relatório como
**X — Extensões**.

A pergunta central: **quem decide o que roda, e com que permissão.**

---

## Onde procurar

| Caminho | O que é achado |
|---|---|
| Entrada do evento | O hook ou a ferramenta trata como confiável o que recebe (nome de arquivo, comando, texto do usuário ou do modelo). Esse dado vem de fora e passa pelas mesmas checagens do A03 |
| Falha da extensão | Extensão de bloqueio que, ao dar erro ou estourar tempo, deixa a ação passar (falha aberta). Conferir o que o sistema hospedeiro faz quando a extensão sai com erro |
| Permissão | Extensão roda com mais acesso que precisa: lê o ambiente inteiro, escreve fora da própria pasta, abre rede sem motivo |
| Origem | Plugin ou ferramenta carregados de caminho ou URL configurável sem fixar versão ou conferir integridade |
| Desvio | O bloqueio cobre uma forma de chegar ao recurso e não outra (bloqueia `Read` de `.env`, mas não `cat .env` no shell) |
| Saída | O que a extensão devolve ao hospedeiro (log, mensagem, contexto para o modelo) carrega segredo ou dado que não deveria |

A severidade segue a tabela geral da `SKILL.md`.
