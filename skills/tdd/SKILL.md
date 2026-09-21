---
name: tdd
description: >
  Ciclo red-green de TDD: um teste que falha por vez, depois a implementação
  mínima. Use quando o usuário for implementar um comportamento novo e quiser o
  teste primeiro, ou mencionar TDD, red-green ou test-first. Para escrever teste
  sobre código que já existe, não é esta skill — isso é cobertura retroativa.
  Para revisar teste já escrito, use /code-review.
disable-model-invocation: true
argument-hint: [comportamento a implementar]
allowed-tools: Bash(npm test *) Bash(npx vitest *) Bash(mvn test *) Bash(mvn -q test *) Bash(./gradlew test *)
---

<!--
  Adaptado de mattpocock/skills — skills/engineering/tdd
  commit de origem: 0877403d1e867fd9d574117e9b34ade404f36d2a
  Alterações locais: Step 0 (detecção de stack e saúde da suíte), stacks/*.md,
  frontmatter com disable-model-invocation e allowed-tools.
-->

# Test-Driven Development

TDD é o loop red → green. Esta skill é a referência que faz esse loop produzir
testes que valem a pena manter: o que é um bom teste, onde ele mora, os
anti-padrões, e as regras do ciclo. Todas as seções valem em **todo** ciclo —
consultar antes e durante, não depois.

---

## Step 0 — Detectar stack e confirmar a suíte (obrigatório, antes de tudo)

```bash
ls package.json pom.xml build.gradle build.gradle.kts pyproject.toml 2>/dev/null
```

| Encontrado | Carregar | Comando base |
|---|---|---|
| `package.json` | `stacks/node.md` | ler o script `test` do manifesto |
| `pom.xml` | `stacks/java.md` | `mvn -q test` |
| `build.gradle` / `.kts` | `stacks/java.md` | `./gradlew test` |
| nenhum / ambíguo | — | **perguntar** antes de escrever qualquer teste |

Monorepo (`workspaces`, `turbo.json`, `pnpm-workspace.yaml`, módulos Maven):
perguntar em qual pacote/módulo trabalhar antes de continuar.

**Rodar a suíte UMA VEZ antes do primeiro teste.** Se já estiver vermelha por
outro motivo, parar e avisar — não dá para fazer red → green em cima de uma
suíte quebrada, porque o vermelho deixa de significar alguma coisa.

Carregar apenas o arquivo de `stacks/` que corresponde ao detectado.

---

## O que é um bom teste

Testes verificam **comportamento através de interfaces públicas**, não detalhes de
implementação. O código pode mudar inteiro; os testes não deveriam. Um bom teste
lê como especificação — "usuário consegue finalizar compra com carrinho válido"
diz exatamente qual capacidade existe — e sobrevive a refatorações porque não se
importa com a estrutura interna.

Ver `tests.md` para exemplos e `mocking.md` para quando (não) mockar.

---

## Seams — onde os testes ficam

Um **seam** é o lugar onde dá para alterar comportamento sem editar naquele lugar —
é onde a interface pública do módulo mora. Testes ficam em seams, nunca contra
internals. Vocabulário completo (module, interface, depth, seam, adapter, leverage,
locality) e o princípio "a interface é a superfície de teste": skill `codebase-design`.

**Testar somente em seams pré-acordados.** Antes de escrever qualquer teste,
listar os seams e **confirmar com o usuário**. Nenhum teste é escrito num seam não
confirmado. Não dá para testar tudo — acordar os seams na frente é como o esforço
de teste cai nos caminhos críticos e na lógica complexa, em vez de em toda borda
imaginável.

Perguntar: "qual é a interface pública, e quais seams a gente testa?"

---

## Anti-padrões

- **Acoplado à implementação** — mocka colaboradores internos, testa métodos
  privados, ou verifica por canal lateral (consultar o banco em vez de usar a
  interface). O sinal: o teste quebra numa refatoração sem que o comportamento
  tenha mudado.

- **Tautológico** — a asserção recalcula o valor esperado do mesmo jeito que o
  código calcula (`expect(add(a,b)).toBe(a+b)`), então passa por construção e
  nunca pode discordar do código. Valor esperado tem que vir de fonte
  independente: um literal conhecido, um exemplo resolvido na mão, a spec.

- **Fatia horizontal** — escrever todos os testes primeiro e depois toda a
  implementação. Teste em lote verifica comportamento *imaginado*: você testa o
  formato das coisas em vez do comportamento real, os testes ficam insensíveis a
  mudanças de verdade, e você se compromete com a estrutura do teste antes de
  entender a implementação. Trabalhar em **fatias verticais**: um teste → uma
  implementação → repete, cada teste respondendo ao que o ciclo anterior ensinou.

---

## Regras do loop

- **Vermelho antes do verde.** Escrever o teste que falha primeiro, depois só o
  código suficiente para passar. Não antecipar testes futuros nem adicionar
  funcionalidade especulativa.
- **Uma fatia por vez.** Um seam, um teste, uma implementação mínima por ciclo.
- **Rodar o teste e mostrar o vermelho** antes de implementar. Vermelho presumido
  não conta — se o teste passa de primeira, ele está errado ou o comportamento já
  existe.
- **Refatoração não faz parte do loop.** Pertence à etapa de revisão
  (`/code-review`), não ao ciclo red → green.
