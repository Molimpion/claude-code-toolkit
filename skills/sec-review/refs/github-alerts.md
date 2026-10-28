# Alertas do GitHub

Carregar no **Step 0** só quando o remoto for GitHub e houver sinal de alerta
ativado. Roda junto com o Step 1. Entra na cobertura do relatório como
**G — Alertas do GitHub**.

Confirmar o repositório:

```bash
gh repo view --json nameWithOwner -q .nameWithOwner
```

Consultar os alertas **abertos**, sempre por `GET` e sem trazer o valor do
segredo (o endpoint de secret scanning devolve o segredo no campo `secret`):

```bash
gh api "repos/<repo>/dependabot/alerts?state=open" --paginate \
  -q '.[] | {pkg: .dependency.package.name, ghsa: .security_advisory.ghsa_id, sev: .security_advisory.severity, manifest: .dependency.manifest_path}'
gh api "repos/<repo>/secret-scanning/alerts?state=open" --paginate \
  -q '.[] | {tipo: .secret_type_display_name, criado: .created_at, url: .html_url}'
gh api "repos/<repo>/code-scanning/alerts?state=open" --paginate \
  -q '.[] | {regra: .rule.id, sev: .rule.security_severity_level, arquivo: .most_recent_instance.location.path, linha: .most_recent_instance.location.start_line}'
```

| Resposta | Registrar |
|---|---|
| Lista (vazia ou não) | Os alertas entram como candidatos: Dependabot no Step 1, secret scanning no Step 2, code scanning no Step 3. Passam pelo Step 5 como qualquer candidato |
| 404 ou "not enabled" | O recurso não está ativado no repositório |
| 403 | O token não tem permissão de leitura de alertas. Lacuna, não zero alertas |
| `gh` ausente ou sem login | Não verificável |

Alerta é evidência, não veredito: o Dependabot aponta o range do manifesto, e a
regra da versão instalada do Step 1 continua valendo. Nunca copiar para o
relatório o valor de um segredo, mesmo que apareça em outra saída.
