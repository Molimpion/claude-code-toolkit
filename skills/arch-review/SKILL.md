---
name: arch-review
description: >
  Varredura de arquitetura de um repositório: encontra módulos rasos, aplica o
  teste da deleção e apresenta candidatos de aprofundamento para o usuário
  escolher. Use quando o usuário pedir revisão de arquitetura, disser que o
  código está difícil de mudar ou de navegar, ou pedir refatoração estrutural que
  atravessa mais de um módulo. Para limpeza dentro de um diff, use /simplify;
  para revisar um PR, /code-review. A skill codebase-design fornece só o
  vocabulário — para levantar candidatos, é esta aqui.
disable-model-invocation: true
argument-hint: "[módulo ou área] [html]"
---

<!--
  Adaptado de mattpocock/skills — engineering/improve-codebase-architecture
  commit de origem: 0877403d1e867fd9d574117e9b34ade404f36d2a
  Alterações locais: Step 0 de descoberta de contexto; relatório em markdown por
  padrão (HTML só sob pedido); Step 4 delega para a skill grilling
  e /domain-modeling; efeitos colaterais em CONTEXT.md/ADR simplificados.
-->

# Arch Review

Encontrar **oportunidades de aprofundamento** — refatorações que transformam
módulos rasos em profundos. O objetivo é testabilidade e facilidade de navegação.

Vocabulário obrigatório: skill `codebase-design`. Usar *module*, *interface*,
*depth*, *seam*, *adapter*, *leverage*, *locality* exatamente como definidos lá.
Não derivar para "componente", "serviço" ou "camada". Se a skill
`codebase-design` não estiver disponível, avisar e parar — sem o vocabulário
comum a análise vira conselho genérico.

---

## Step 0 — Descobrir contexto do projeto

Parar no primeiro que existir em cada categoria.

```bash
ls CONTEXT.md docs/CONTEXT.md .claude/CONTEXT.md 2>/dev/null
ls -d docs/adr docs/decisions docs/architecture adr 2>/dev/null
ls ARCHITECTURE.md docs/architecture.md 2>/dev/null
```

| Fonte | Uso |
|---|---|
| `CONTEXT.md` | vocabulário de domínio — nomear seams com os termos do negócio |
| `docs/adr/` | decisões já tomadas — **não** re-litigar |
| `ARCHITECTURE.md` | estrutura declarada — comparar com a real |

**ADRs:** listar os títulos primeiro (`ls` do diretório) e ler **somente** os que
tocam a área sob análise. Nunca ler todos.

**`CLAUDE.md` não conta** como fonte de domínio: já está em contexto e é
instrução para o agente, não vocabulário do negócio.

**Snapshot empacotado** (saída de repomix e afins): usar apenas com `grep` para
localizar arquivo. Nunca ler inteiro — pode passar de 100k tokens. Preferir
sempre o código real no disco.

Se nenhuma fonte existir: **dizer isso explicitamente** e prosseguir com
confiança reduzida. Não presumir arquitetura a partir de nomes de pasta.

---

## Step 1 — Definir escopo antes de escanear

Aprofundar módulo que ninguém toca não paga. Decidir *onde* olhar antes de olhar:

- Usuário indicou módulo, subsistema ou dor específica → usar isso e pular o resto.
- Caso contrário: `git log --oneline -80 --name-only` para achar os pontos quentes
  — os arquivos e áreas que aparecem repetidamente. Se as mudanças estiverem
  espalhadas sem ponto quente claro, ampliar.

---

## Step 2 — Explorar e aplicar o teste da deleção

Explorar organicamente, anotando onde há fricção:

- Entender um conceito exige pular entre muitos módulos pequenos?
- Módulos **shallow** — interface quase tão complexa quanto a implementação?
- Funções puras extraídas só por testabilidade, mas o bug real mora em como são
  chamadas (sem **locality**)?
- Módulos acoplados vazando através do seam?
- Partes sem teste, ou difíceis de testar pela interface atual?

**Teste da deleção** em tudo que parecer raso: se eu apagar isso, a complexidade
some ou reaparece espalhada nos chamadores? "Reaparece espalhada" é o sinal bom —
o módulo está pagando o próprio custo. "Some" significa pass-through.

Só vira candidato o que passa no teste da deleção. Sem isso a lista fica infinita.

---

## Step 3 — Apresentar candidatos (markdown por padrão)

**Não propor interface nova ainda.** Só apresentar e perguntar qual explorar.

Para cada candidato:

```
### <nome do candidato>   ·   Força: Forte | Vale explorar | Especulativo

**Arquivos:** <caminhos>
**Problema:** por que a estrutura atual causa fricção
**Solução:** em português claro, o que mudaria
**Ganho:** em termos de leverage (chamadores) e locality (manutenção),
           e como os testes melhorariam
**Antes → Depois:** esboço curto em texto ou mermaid da forma atual e da proposta
```

Nomear usando o vocabulário de `CONTEXT.md` quando existir: "o módulo de entrada
de Pedido", não "o PedidoHandler".

**Conflito com ADR:** só levantar quando a fricção for real o bastante para
justificar reabrir a decisão, e marcar claramente ("contradiz o ADR-0007, mas
vale reabrir porque…"). Não listar toda refatoração teórica que um ADR proíbe.

Fechar com **Recomendação principal**: qual atacar primeiro e por quê.

Se o usuário passar `html` como argumento: gerar em vez disso um HTML
autocontido em `$TMPDIR` (ou `/tmp`), abrir com `xdg-open`, e informar o caminho
absoluto. Nunca escrever o relatório dentro do repositório.

Terminar perguntando: **"qual desses você quer explorar?"**

---

## Step 4 — Aprofundar o candidato escolhido

Rodar a skill `grilling`, semeando a árvore de decisão com estas raízes:

- Qual comportamento fica **atrás** do seam e qual continua exposto?
- O que varia através desse seam hoje? (um adapter = seam hipotético;
  dois = seam real — não criar seam sem variação real)
- Quais chamadores mudam, e quantos?
- Quais testes atuais sobrevivem sem alteração? Os que quebrarem estavam
  testando implementação, não comportamento — isso é informação, não obstáculo.
- Qual o menor primeiro passo que já dá ganho e pode ser mergeado sozinho?

Escalar ao tamanho do candidato: refatoração pequena e reversível não precisa
da árvore inteira.

Só depois de a fronteira esvaziar, propor a interface concreta.

**Efeitos colaterais durante a conversa:**

- Nomeou um módulo com um conceito que não está no `CONTEXT.md` → oferecer
  adicionar o termo. Criar o arquivo se não existir.
- Usuário rejeitou o candidato por um motivo estrutural que vai valer daqui a
  seis meses → oferecer registrar como ADR: *"quer que eu registre isso como ADR
  para revisões futuras não sugerirem de novo?"* Só oferecer quando o motivo
  seria mesmo necessário para um explorador futuro — pular motivos passageiros
  ("agora não dá") e óbvios.
- Nunca escrever em `CONTEXT.md` ou criar ADR sem confirmação explícita.
