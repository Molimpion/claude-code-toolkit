---
name: post-refactor
description: >
  Varredura do que uma sequência de commits ou PRs mergeados deixou para trás:
  regressão, erro engolido, lógica duplicada, abstração sem uso, valor mágico,
  teste fraco ou instável. Use quando o usuário disser que terminou uma
  refatoração, que vários PRs entraram, ou pedir para conferir o estado do código
  depois de uma série de mudanças. Para revisar um diff ou PR, use /code-review;
  para arquitetura do repositório inteiro, arch-review; para segurança,
  sec-review.
disable-model-invocation: true
argument-hint: "[range git opcional, ex.: v1.2.0..HEAD]"
allowed-tools: Bash(git log *) Bash(git diff *) Bash(git show *) Bash(git describe *) Bash(git status *) Bash(git rev-parse *) Bash(npm test *) Bash(npm run *) Bash(npx tsc *) Bash(mvn *) Bash(./gradlew *)
---

# Post-Refactor

Pergunta que esta skill responde: **o código que mudou ficou melhor, ou ficou
regressão e sujeira para trás?**

Não é revisão de PR (cada PR já foi revisado) nem revisão de arquitetura. O
alvo é o efeito somado de vários commits: o que nenhum PR isolado mostra.

**Nunca alterar o repositório.** Achados e correções vão em texto; o usuário
decide o que aplicar.

---

## Step 0 — Range

Com range informado, usar exatamente esse.

Sem range, mostrar o histórico recente e **perguntar**:

```bash
git describe --tags --abbrev=0 2>/dev/null
git log --oneline --first-parent -20
```

Sugerir um range (desde a última tag, ou desde o primeiro commit da série que
parece relacionada) e esperar confirmação. Range errado gera relatório sobre o
código errado.

Range que cruza áreas sem relação → agrupar os arquivos por área e relatar cada
grupo separado.

---

## Step 1 — Superfície alterada

```bash
git log --oneline <range>
git diff --stat <range>
git diff --name-only <range>
```

Separar: código de produção, testes, configuração e dependências, schema e
migration. Ler só os arquivos alterados e os vizinhos diretos que eles chamam.
Nunca o repositório inteiro.

---

## Step 2 — Verificação do projeto

Rodar o que o projeto declara: scripts `typecheck`, `lint` e `test` do
`package.json`; `mvn -q verify` ou `./gradlew check` no Java. Sem script
declarado, perguntar qual comando usar.

Comando que não rodou (ausente, erro de ambiente) é **lacuna**, não aprovação:
registrar no relatório o que não foi verificado e por quê.

Teste que falhou: rodar de novo **uma vez**, só aquele teste. Passou na segunda
→ relatar como instável com a evidência das duas execuções, não como resolvido.

---

## Step 3 — Código alterado

Para cada arquivo de produção alterado:

| Procurar | Por quê |
|---|---|
| Mudança de comportamento sem teste novo ou alterado: valor padrão, formato de resposta, tratamento de erro, ordem, filtro de consulta | É a regressão que a série de commits esconde. Cada PR parecia neutro; o somatório não é |
| `catch` que engole o erro, `catch` genérico, fallback que troca erro por valor vazio | Falha vira dado errado silencioso |
| `any`, asserção `as X` sobre dado externo, `!` de não-nulo novo | O tipo deixa de proteger justo na fronteira |
| Entidade de persistência devolvida direto na resposta | Campo interno ou sensível passa a vazar na serialização |
| Mesma lógica em dois lugares, ou helper novo que duplica um existente | As cópias divergem na próxima mudança |
| Abstração nova com um único chamador (interface, classe base, genérico, opção de configuração) | Aplicar o teste da deleção (vocabulário em `codebase-design`): apagar e reescrever no chamador deixa o código pior? Se não, é peso |
| Número ou string com significado de negócio solto no código | Regra de negócio sem nome |
| Comentário ou documentação que descreve o comportamento antigo | Mente para o próximo leitor |
| Código morto: export sem uso, branch inalcançável, flag que não muda nada | Sobra da refatoração |

Não pedir abstração para lógica que aparece uma vez. Duplicação só é achado
quando as cópias já divergiram ou vão mudar juntas.

---

## Step 4 — Testes alterados e faltantes

| Procurar | Por quê |
|---|---|
| Comportamento alterado no Step 3 sem teste que o cubra | Nada impede a regressão de voltar |
| `.skip`, `.only`, `@Disabled`, teste comentado | Teste desligado aprova qualquer coisa |
| `toThrow()` sem mensagem ou tipo; asserção por negação (`not.toBe`) em resultado determinístico | Passa com o comportamento errado |
| Teste que verifica chamada interna ou mock de colaborador em vez do resultado | Quebra na refatoração e não pega regressão |
| `sleep`, timeout fixo, relógio real, rede, ordem de execução, estado global compartilhado | Fonte de instabilidade |
| Nome do teste descreve implementação, não comportamento | Se o projeto tem convenção própria, ela ganha: apontar a divergência sem corrigir |

---

## Severidade

| Nível | Critério |
|---|---|
| BLOQUEIA | Regressão provável, verificação vermelha, teste instável reproduzido, dado sensível vazando, perda de dado |
| CORRIGIR | Comportamento alterado sem teste, duplicação que já divergiu, erro engolido em caminho de produção |
| PODE ESPERAR | Valor mágico, comentário desatualizado, abstração sem uso, nome de teste |
| OBSERVAÇÃO | Área conferida sem problema, ou ponto a acompanhar |

Achado de segurança que apareça aqui é registrado como BLOQUEIA e o relatório
sugere rodar a `sec-review`. Esta skill não faz auditoria de segurança.

---

## Relatório

```markdown
## Post-refactor: <range>

Verificação: <passou | falhou | parcial — o que não rodou e por quê>

### Achados
- [NÍVEL] `arquivo:linha` — o problema. Correção proposta. (verificado por: leitura | comando | teste)

### Testes
- cobertura do que mudou, instabilidade observada

### Próximo passo
- uma ação concreta, ou "nenhum"
```

Achados em ordem de severidade. Sem achado de BLOQUEIA a PODE ESPERAR: dizer
isso e listar o que foi conferido. Não inflar para o relatório parecer
produtivo.
