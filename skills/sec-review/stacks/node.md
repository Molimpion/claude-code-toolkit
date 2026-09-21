# Stack — JavaScript / TypeScript (Express, NestJS, Fastify)

Carregado no Step 0 quando existe `package.json`.

Escopo desta skill: **Express, NestJS e Fastify**. Outro framework → aplicar o
fallback do §1 e marcar A01 como cobertura parcial no relatório.

Estrutura: **§1 detecção**, **§2 invariantes**, **§3 por framework**,
**§4 TypeScript**.

---

## §1 Detectar framework e versões

```bash
npm ls --depth=0
cat package.json | grep -E '"(express|fastify|@nestjs/core)"'
ls tsconfig.json 2>/dev/null
```

Registrar as versões **instaladas** (lockfile), não os ranges do manifesto.

**Fora do escopo (outro framework):** não pular A01. Achar onde as rotas são
registradas, identificar o que embrulha o handler, comparar uma rota que deveria
ser pública com uma que deveria ser privada — a diferença revela o mecanismo de
auth. Avaliar as demais contra ele e marcar **cobertura parcial**, nomeando o
framework.

---

## §2 Invariantes (valem nos três)

### A02 — Cripto
Senha com `createHash('md5'|'sha1')` ou sem salt → `bcrypt`, `argon2`, `scrypt`.
Token de sessão, convite ou recuperação com `Math.random()` → `crypto.randomBytes`
ou `crypto.randomUUID`. `rejectUnauthorized: false` em cliente TLS.
Comparação de segredo com `===` em fluxo de auth → `crypto.timingSafeEqual`.

### A03 — Injeção
- ORM: métodos `raw` / `unsafe` com concatenação. Template com parâmetro é seguro.
- Driver puro (`pg`, `mysql2`, `sqlite3`): template string no lugar de `$1` / `?`.
- `child_process.exec` / `execSync` com input do usuário → `execFile` com array.
- `fs` / `path` com nome vindo de request sem `path.resolve` e sem confinar ao
  diretório base (checar que o resultado começa pelo base).
- NoSQL: objeto do body indo direto ao filtro — aceitar só string onde a query
  espera string.
- `eval`, `new Function`, `vm.runInNewContext` com qualquer parte do usuário.
- XSS: relevante onde a API devolve HTML ou o dado é renderizado depois sem
  escape. Interpolação em template engine escapa por padrão na maioria; verificar
  uso de filtro `raw`/`safe`.

### A04 / A07 — Auth e sessão
JWT: assinatura verificada de fato (`verify`, nunca `decode` para autorizar);
algoritmo fixado no servidor; `none` recusado; expiração presente; segredo vindo
de variável de ambiente. Logout que não invalida nada com token de longa duração.
Cookie de sessão sem `httpOnly`, `secure`, `sameSite`. Login e recuperação de
senha sem trava de tentativa. Token de reset sem expiração ou reutilizável.

### A08 — Integridade
Upload sem limite de tamanho, sem checar o tipo real (não confiar em extensão nem
no `Content-Type` enviado), com nome original usado no path.
Webhook processado antes de verificar a assinatura, ou com o corpo já parseado —
a verificação exige o corpo bruto.

### A09 — Logs
Logger recebendo request inteiro, corpo de login, token, cookie, ou usuário
completo. Erro de auth logando a credencial tentada.

### A10 — SSRF
`fetch` / `axios` / `undici` com URL vinda do usuário sem allowlist de host.
Verificar redirecionamento seguido automaticamente e destino em faixa interna.

---

## §3 Controle de acesso por framework (A01)

Comum aos três, e o achado mais frequente: **ID vindo do path, query ou body
usado em consulta sem comparar com o dono da sessão** (IDOR). Procurar
`findById`, `findUnique`, `findOne` recebendo valor que veio do request.

### Express

A auth mora em middleware, e **a ordem de registro decide tudo**.

Verificar:
- `app.use(auth)` registrado **depois** das rotas que deveria proteger — não
  protege nada. Ler a ordem no arquivo de bootstrap, não só a existência.
- Router montado antes do middleware global.
- Middleware aplicado por rota (`router.get('/x', auth, handler)`) — confirmar
  que está em todas as rotas do grupo, não só nas primeiras.
- `next()` chamado dentro do middleware de auth mesmo quando a verificação falha.
- Erro de auth respondido mas sem `return`, deixando o handler executar depois.

```bash
grep -rn "app.use(\|router.use(" src/ | head -30
grep -rn "router\.\(get\|post\|put\|patch\|delete\)" src/
```

### NestJS

A auth mora em guard: `@UseGuards` no handler, no controller, ou global via
`APP_GUARD`.

Verificar:
- Guard global registrado como provider `APP_GUARD` — se existir, rotas sem
  `@Public()` (ou decorator equivalente) estão protegidas; sem ele, cada
  controller precisa do próprio.
- `@UseGuards` no controller mas o **service chamado por outro caminho**
  (listener de evento, cron, outro controller) — a proteção não acompanha.
- `@Roles('ADMIN')` presente mas sem o guard de papel registrado — a anotação
  vira decoração inerte.
- `ValidationPipe` ausente: ver §4, os DTOs não validam nada sem ele.
- Interceptor de serialização ausente em resposta que devolve entidade completa
  (vaza hash de senha, token, campos internos).

```bash
grep -rn "@UseGuards\|@Roles\|APP_GUARD\|@Public" src/
grep -rn "ValidationPipe\|useGlobalPipes" src/
```

### Fastify

A auth mora em hook (`onRequest`, `preHandler`), e o ponto crítico é o **escopo
de encapsulamento**.

Verificar:
- Hook registrado fora do plugin cujas rotas deveria proteger — em Fastify o
  escopo é encapsulado por padrão, então `addHook` num plugin **não** afeta
  rotas registradas em outro.
- `fastify-plugin` usado para quebrar o encapsulamento intencionalmente: se o
  plugin de auth usa `fp()`, ele vaza para o escopo pai — confirmar se isso é o
  desejado ou acidente.
- Rota com `preHandler` no schema de algumas rotas e faltando em outras do mesmo
  arquivo.
- Schema de validação (`schema.body`) ausente — em Fastify o schema é a validação
  em runtime; sem ele o body não é checado, mesmo com tipo TS declarado.

```bash
grep -rn "addHook\|preHandler\|onRequest" src/
grep -rn "fastify-plugin\|fp(" src/
grep -rn "schema:" src/ | head -20
```

---

## §4 TypeScript — tipo não é validação

**Tipos somem em runtime.** `interface` e `type` não impedem nada.

| Padrão | Por que é risco |
|---|---|
| `req.body as CreateUserDto` | Asserção, não validação. Exige parser em runtime: Zod/Valibot (Express, Fastify), `ValidationPipe` + class-validator (NestJS), ou `schema` da rota (Fastify). |
| `as any` / `as unknown as X` num caminho de request | Apaga a garantia do compilador. Tratar como fronteira não validada. |
| `@ts-expect-error` / `@ts-ignore` perto de query, path ou comando | Esconde exatamente o erro que causa injeção. |
| `process.env.SEGREDO!` | Não garante presença; a app sobe com o segredo `undefined` e falha aberto. Validar env na inicialização. |
| `...req.body` espalhado em `create` / `update` do ORM | Mass assignment — usuário envia `role: 'ADMIN'` e passa. Selecionar campos explicitamente. |
| `Record<string, any>` / `object` vindo do request | Perde toda checagem; qualquer sink adiante fica sem garantia. |
| DTO do NestJS sem `ValidationPipe` | Os decorators não rodam sozinhos; o DTO vira só tipo. |
| `FastifyRequest<{ Body: X }>` sem `schema.body` | O genérico é só tipagem; a validação em runtime é o schema. |
| Genérico do ORM contornado com `as` | Quebra a parametrização tipada, que era a defesa contra SQLi. |
| `strict: false` / `noImplicitAny: false` | Contexto: eleva a confiança de que asserções escondem problema real. INFO isolado. |

Regra: **onde houver `as`, `!` ou `any` entre o request e o sink, tratar o dado
como não confiável**, mesmo que o tipo diga o contrário.

```bash
grep -rn "as any\|as unknown\|@ts-ignore\|@ts-expect-error" src/ | head -40
grep -rn "req\.body as\|request\.body as\|body as " src/
grep -rn "\.\.\.req\.body\|\.\.\.request\.body" src/
grep -rn '"strict"' tsconfig.json
```

---

## Pistas por grep (§2)

```bash
grep -rn "createHash('md5'\|createHash('sha1'\|Math.random()" src/
grep -rn "queryRawUnsafe\|executeRawUnsafe\|\.query(\`" src/
grep -rn "exec(\|execSync(\|eval(\|new Function(" src/
grep -rn "jwt.decode\|algorithms:\|rejectUnauthorized" src/
grep -rn "origin: *'\*'\|origin: *true" src/
grep -rn "httpOnly\|sameSite\|secure:" src/
```

São **pistas, não achados**. Confirmar contexto e passar pelo filtro do Step 5.
