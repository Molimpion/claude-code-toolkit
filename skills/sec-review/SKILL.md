---
name: sec-review
description: >
  Auditoria de segurança de um repositório inteiro, ancorada no OWASP Top 10,
  com filtro anti-falso-positivo e correções propostas em texto (nunca
  aplicadas). Use quando o usuário pedir auditoria de segurança, perguntar se o
  código está seguro, ou pedir para procurar vulnerabilidades, IDOR, injeção,
  SSRF ou segredos expostos. Para revisar apenas as mudanças pendentes de uma
  branch, use /security-review.
disable-model-invocation: true
argument-hint: [path opcional]
allowed-tools: Bash(npm audit *) Bash(npm ls *) Bash(git ls-files *) Bash(git log *) Bash(git fetch *) Bash(git status *) Bash(git rev-list *) Bash(mvn dependency*) Bash(./gradlew dependenc*) Bash(grep *) Bash(find *)
---

# Security Review

Auditoria estática de segurança de um repositório. Postura de **pesquisador de
segurança**: contexto, fluxo de dados e mitigação já presente no framework — não
casamento de padrão.

**Nunca alterar o repositório.** Correções são propostas em texto.

---

## Princípios (valem em todo achado)

1. **Evidência antes de severidade.** Um padrão suspeito não é achado. Achado
   exige caminho de exploração plausível.
2. **Versão instalada, não a mais recente.** CVE se aplica à versão do lockfile.
   "Existe versão mais nova" sem advisory é INFO, nunca HIGH.
3. **Rastrear imports.** Auth pode estar num wrapper, middleware, decorator ou
   helper importado. Ausência no arquivo não é ausência no sistema.
4. **Filtro obrigatório.** Todo candidato passa por `refs/false-positives.md`
   antes de virar achado. Sem exceção.
5. **Nunca aplicar patch.** Propor com antes/depois e deixar a decisão com o
   usuário.

---

## Step 0 — Escopo e stack

Path informado → só esse escopo. Senão → raiz do repositório.

```bash
ls package.json pom.xml build.gradle build.gradle.kts 2>/dev/null
ls turbo.json nx.json pnpm-workspace.yaml go.work 2>/dev/null
```

| Encontrado | Carregar |
|---|---|
| `package.json` | `stacks/node.md` |
| `pom.xml` / `build.gradle*` | `stacks/java.md` |
| ambos (monorepo) | perguntar qual módulo auditar antes de continuar |
| nenhum | avisar que a stack não é coberta e perguntar antes de prosseguir |

Registrar as versões **instaladas** (lockfile) das dependências relevantes — vão
no cabeçalho do relatório.

Priorizar código que mudou recentemente: `git log --oneline -50 --name-only`.
Código novo tem mais bug do que código estável.

### Atualidade do código auditado (obrigatório)

Auditar uma branch defasada produz relatório sobre código que já não existe.

```bash
git fetch --quiet 2>/dev/null
git status -sb | head -1
git rev-list --left-right --count origin/HEAD...HEAD 2>/dev/null
```

Se o HEAD estiver atrás da branch de integração, **registrar no cabeçalho do
relatório**: "esta branch está N commits atrás de <branch>; achados podem já ter
sido corrigidos". Se N passar de 20, dizer isso antes de continuar e perguntar se
o usuário quer auditar a branch atual.

Sem rede ou sem remoto: registrar "atualidade não verificável" no cabeçalho. Nunca
omitir — a ausência de aviso é lida como código atual.

---

## Step 1 — Dependências

Node: `npm audit --omit=dev`
Java: `mvn dependency-check:check` se o plugin existir; senão listar versões e
sinalizar que a checagem de CVE não foi feita — **não inventar CVE**.

Regras: só reportar com advisory identificado (CVE/GHSA). Citar a versão
instalada, não o range do manifesto. DevDependency sem uso em runtime → INFO.

---

## Step 2 — Segredos e exposição

`refs/secrets.md`. O teste que importa: o arquivo está **rastreado pelo git**
(`git ls-files`), não apenas presente no disco.

---

## Step 3 — Varredura por categoria (OWASP Top 10 como espinha)

Marcar cada categoria como coberta, não-aplicável ou não-verificável. O relatório
mostra essa cobertura — o usuário precisa saber o que **não** foi olhado.

| # | Categoria | O que procurar |
|---|---|---|
| A01 | Controle de acesso quebrado | ID vindo do cliente usado em query sem checar dono (IDOR/BOLA); rota sem middleware/guard; papel checado só no front; path traversal em download |
| A02 | Falhas criptográficas | hash obsoleto (MD5, SHA1) para senha; segredo hardcoded; TLS desabilitado; token previsível (`Math.random`, `Random` sem seed seguro); PII sem criptografia em repouso quando o projeto declara precisar |
| A03 | Injeção | SQL concatenado ou raw sem parâmetro; comando de SO com input do usuário; XSS refletido/armazenado; LDAP/NoSQL injection; template injection |
| A04 | Design inseguro | fluxo de recuperação de senha sem expiração; ausência de rate limit em login; operação financeira sem idempotência |
| A05 | Configuração incorreta | debug ligado em produção; CORS `*` com credenciais; stack trace vazando ao cliente; console de admin exposto; bucket/dir público sem intenção |
| A06 | Componentes desatualizados | resultado do Step 1 |
| A07 | Falhas de autenticação e sessão | senha sem política mínima; sessão sem expiração; token sem verificação de assinatura; ausência de invalidação no logout; brute force sem trava |
| A08 | Falhas de integridade | desserialização de dado não confiável; upload sem validação de tipo e tamanho; dependência de fonte não confiável; webhook sem verificação de assinatura |
| A09 | Falhas de log e monitoramento | senha, token ou sessão inteira em log; evento de segurança sem registro; PII em log |
| A10 | SSRF | requisição para URL controlada pelo usuário sem allowlist |

Detalhes específicos da stack no arquivo carregado no Step 0.

---

## Step 4 — Fluxo de dados

Para cada achado candidato, desenhar o caminho:

```
entrada (query, body, header, cookie, upload, param)
  → validação
  → autenticação
  → autorização (dono, papel, tenant)
  → sink (banco, fetch, HTML, filesystem, processo, pagamento)
```

O achado só existe se houver caminho da entrada até o sink **sem** barreira. Se
qualquer etapa barra, descartar ou rebaixar. Vulnerabilidade real costuma
aparecer entre arquivos: auth no controller, mas o service é chamado direto de
outro lugar.

---

## Step 5 — Filtro anti-falso-positivo (obrigatório)

`refs/false-positives.md`. Aplicar em **todos** os candidatos antes de escrever o
relatório. Os descartados vão para uma seção própria com o motivo — isso é o que
dá confiança no resto.

---

## Severidade

| Nível | Critério |
|---|---|
| CRITICAL | Exploração imediata e sem pré-requisito: SQLi, RCE, bypass de auth, segredo de produção rastreado no git |
| HIGH | Exploit claro com pré-requisito simples: IDOR, XSS armazenado, webhook sem assinatura, senha com hash obsoleto |
| MEDIUM | Exige encadeamento ou condição de deploy: CORS mal configurado, rate limit ausente em endpoint sensível |
| LOW | Boa prática pontual, impacto limitado |
| INFO | Sem exploração: versão atrás da latest sem CVE, header de segurança ausente, hardening opcional |

**Proibido:** CRITICAL ou HIGH apenas por ausência de header, ausência de CSP, ou
dependência desatualizada sem advisory.

Todo achado leva **confiança** (ALTA / MÉDIA / BAIXA). Confiança BAIXA que não
seja vulnerabilidade clara vai para a seção de descartados, não para o relatório.

---

## Step 6 — Relatório

Ordem fixa:

1. **Cabeçalho** — escopo, stack e versões instaladas, data, o que foi excluído
2. **Resumo** — contagem por severidade
3. **Cobertura OWASP** — tabela A01–A10 marcando coberto / não-aplicável / não-verificável
4. **Achados por categoria** — cada um com: severidade, confiança, arquivo e
   linha, trecho real, por que é explorável, correção acionável, referência
   OWASP/CWE
5. **Dependências**
6. **Segredos**
7. **Correções propostas** (só CRITICAL e HIGH) — antes/depois, precedido de:
   *"Revise cada correção antes de aplicar. Nada foi alterado no repositório."*

   **Ordem de aplicação (obrigatório).** Severidade responde "o que é mais
   perigoso"; dependência responde "o que aplicar primeiro". São ordens
   diferentes e o relatório precisa das duas. Antes das correções, declarar a
   sequência e o motivo de cada dependência. Quando não houver encadeamento,
   dizer explicitamente que a ordem é livre.

   Encadeamentos a procurar: correção que ativa um caminho hoje inócuo (fechar
   autorização faz um papel mal-atribuído passar a valer); correção que depende
   de outra para ter efeito (validar estado no login não revoga token já
   emitido); correção que muda a forma do dado que outra consome.
8. **Descartados** — candidatos analisados e o motivo de não virarem achado
9. **Limitações** — análise estática, sem teste dinâmico, sem pentest; o que não
   foi verificável

Se zero achados de CRITICAL a LOW: dizer isso e detalhar escopo e limitações. Não
inflar severidade para o relatório parecer produtivo.
