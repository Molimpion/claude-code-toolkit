# Segredos e exposição

Carregar no **Step 2**.

**O teste que decide a severidade:** o arquivo está rastreado pelo git? Estar no
disco e ignorado é normal. Estar no histórico é vazamento.

```bash
git ls-files | grep -Ei '\.(env|pem|key|p12|pfx|jks|keystore)$|credentials|id_rsa|service-account'
git ls-files | grep -Ei 'secret|password' | head -30
```

---

## Prefixos de alto risco (literal em arquivo rastreado)

| Padrão | Origem |
|---|---|
| `AKIA[0-9A-Z]{16}` | chave de acesso AWS |
| `-----BEGIN .*PRIVATE KEY-----` | chave privada |
| `ghp_`, `gho_`, `github_pat_` | GitHub |
| `xox[baprs]-` | Slack |
| `sk_live_`, `rk_live_`, `whsec_` | Stripe (produção) |
| `AIza[0-9A-Za-z\-_]{35}` | Google API |
| `eyJ` longo e fixo em código | JWT hardcoded |
| `postgres(ql)?://[^:]+:[^@]+@` | Postgres com senha embutida |
| `mysql://[^:]+:[^@]+@` | MySQL com senha embutida |
| `mongodb(\+srv)?://[^:]+:[^@]+@` | MongoDB com senha embutida |
| `amqp://[^:]+:[^@]+@` | broker com senha embutida |

---

## Onde procurar além do código de aplicação

- `.github/workflows/`, `.gitlab-ci.yml` — valores literais em `env:` no lugar de
  referência ao cofre de secrets
- `docker-compose*.yml`, `Dockerfile` — `ENV` e `ARG` com valor real
- `application.properties`, `application.yml`, `application-*.yml` — senha de
  banco e segredo de assinatura fora de variável de ambiente
- `next.config`, `vite.config`, `vercel.json` — valor embutido no build
- scripts do manifesto (`package.json`, `pom.xml`) — token em flag de comando
- fixtures, seeds e snapshots de teste
- comentários e strings de exemplo em documentação dentro do repositório

---

## Variáveis que nunca devem ter valor literal no código

Segredo de assinatura de token, URL de banco com credencial, chave de API de
provedor externo, credencial de e-mail ou SMS, chave de storage, senha de broker,
credencial de OAuth.

Verificar também: existem em `.gitignore` **e** ausentes de `git ls-files`.
Padrão ausente do `.gitignore` → MEDIUM mesmo sem arquivo hoje (risco de commit
futuro).

---

## Não reportar

Placeholder óbvio (`your_key_here`, `changeme`, `xxx`, `<token>`), `.env.example`
com valores vazios ou falsos, UUID genérico sem prefixo de provedor, hash de
senha em seed de desenvolvimento documentado, token em teste com nome `mock`,
`fake` ou `dummy`, chave marcada como publicável pelo próprio provedor.

---

## Quando encontrar segredo real

Ordem no relatório, sem exceção:

1. **Rotacionar no painel do provedor primeiro** — remover do código não
   invalida a credencial
2. Substituir por variável de ambiente
3. Corrigir `.gitignore`
4. Verificar se já foi enviado ao remoto (`git log -S '<trecho>' --all`); se sim,
   o histórico precisa ser reescrito ou a credencial considerada comprometida em
   definitivo
