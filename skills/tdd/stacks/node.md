# Stack — Node / TypeScript

Carregado no Step 0 quando existe `package.json`.

---

## Detectar o runner

Ler o manifesto antes de escrever qualquer teste — não assumir:

```bash
cat package.json | grep -A15 '"scripts"'
cat package.json | grep -E 'vitest|jest|node:test|mocha|tap'
```

| Runner | Um arquivo | Watch (o loop) |
|---|---|---|
| Vitest | `npx vitest run caminho/arquivo.test.ts` | `npx vitest caminho/arquivo.test.ts` |
| Jest | `npx jest caminho/arquivo.test.ts` | `npx jest --watch caminho/arquivo.test.ts` |
| `node:test` | `node --test caminho/arquivo.test.ts` | `node --test --watch` |

**Modo watch é o ciclo.** Deixar rodando no arquivo sob teste e usar o vermelho e
o verde ao vivo, em vez de invocar a suíte a cada passo.

Convenção de nome do arquivo: seguir a que já existe no repo (`*.test.ts` vs
`*.spec.ts`, colocado ao lado do código vs em `__tests__/`). Não introduzir uma
terceira convenção.

---

## Fronteiras típicas

Onde mockar, seguindo `mocking.md`:

| Fronteira | Como |
|---|---|
| HTTP externo | MSW ou fake do cliente injetado; evitar `vi.mock` de módulo |
| Banco | preferir banco de teste real (Docker) ou repositório em memória |
| Tempo | `vi.useFakeTimers()` / injetar função de relógio |
| Aleatoriedade | injetar o gerador, não `Math.random()` inline |
| Filas / broker | fake in-memory que expõe o que foi publicado |

`vi.mock` / `jest.mock` de módulo interno é o atalho que gera exatamente o teste
acoplado à implementação descrito em `tests.md`. Preferir injeção de dependência
por parâmetro ou construtor — a mesma regra do `mocking.md`.

---

## TypeScript

Não relaxar tipos para o teste passar (`as any`, `@ts-expect-error`) — se o tipo
atrapalha, o desenho da interface está estranho, e isso é informação do ciclo.

Erro de tipo não é vermelho de TDD. O vermelho tem que vir de asserção que falha,
não de build quebrado.
