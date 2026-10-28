# Isolamento entre organizações (multi-tenant)

Carregar no **Step 0** só quando houver sinal de várias organizações dividindo o
mesmo sistema. Entra na cobertura do relatório como **T — Isolamento**.

Uma organização nunca pode ler, alterar ou inferir dado de outra. O A01 pega a
consulta sem filtro; este arquivo cobre os caminhos que o A01 não olha.

---

## Regra geral: falhar fechado

Organização não identificada na requisição → a operação nega. Código que, sem
organização, roda a consulta sem o filtro é achado, mesmo que nenhum fluxo
atual chegue lá sem organização.

---

## Onde procurar

| Caminho | O que é achado |
|---|---|
| Consulta | `where` sem o identificador da organização, inclusive em `update`, `delete`, contagem e subconsulta. Organização vinda do body ou da query em vez da sessão |
| Cache | Chave sem a organização (`relatorio:mensal` em vez de `org:42:relatorio:mensal`) |
| Busca e índice | Índice de busca compartilhado consultado sem filtro de organização |
| Arquivo | Caminho ou chave de storage sem a organização, acessível trocando o identificador |
| Erro e validação | Mensagem que revela existência de dado de outra organização ("CPF já cadastrado" checando a base inteira) |
| Job e fila | Processo em segundo plano que roda sem contexto de organização, ou recebe a organização no payload sem revalidar |
| Exportação, backup, relatório | Geração que junta organizações ou não filtra |
| Log | Dado de uma organização em log visível para outra |

---

## Severidade

| Situação | Nível |
|---|---|
| Leitura ou escrita de dado de outra organização por usuário comum | CRITICAL |
| Inferência (existência, contagem) sem acesso ao conteúdo | MEDIUM |
| Falta de falha fechada sem caminho atual que chegue sem organização | LOW |
