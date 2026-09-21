# Falsos positivos — filtro obrigatório

Carregar no **Step 5**. Nenhum achado entra no relatório sem passar por aqui.

---

## Portão geral

Responder **sim** às quatro antes de reportar:

1. Existe caminho de exploração plausível — não apenas um padrão suspeito?
2. A entrada é controlada pelo atacante (query, body, header, cookie, upload, param)?
3. Não há validação, sanitização ou autorização no mesmo caminho, nem em
   middleware, guard, decorator ou wrapper acima?
4. O código está em caminho de produção — não em teste, mock, fixture, seed,
   exemplo, storybook, código gerado ou dependência?

Qualquer "não" ou "incerto" → descartar, ou registrar como LOW com confiança
BAIXA e a nota "requer revisão humana".

---

## Padrões que NÃO são achado automático

| Padrão | Por quê |
|---|---|
| Interpolação de variável em query **parametrizada** pelo ORM | O ORM parametriza; só é SQLi com concatenação real ou API `raw`/`unsafe` |
| Template string em log ou mensagem de erro | Não é query |
| Rota sem auth visível **no mesmo arquivo** | Rastrear middleware, guard, decorator e o registro da rota antes de concluir |
| Rota pública por design (health, login, landing) | Avaliar **o que** ela expõe, não "falta login" |
| ID do cliente usado em query junto com o ID da sessão no mesmo `where` | Ownership já garantido |
| `process.env.X` / `System.getenv` sem literal | Uso correto |
| Chave publicável de propósito (prefixo público documentado) | Pública por design |
| Placeholder: `your-key-here`, `changeme`, `xxx`, `.env.example` vazio | Documentação |
| Dependência antiga **sem** advisory | INFO no máximo |
| DevDependency com alerta, sem uso em runtime | Verificar a árvore de import antes |
| Ausência de header de segurança (CSP, HSTS, X-Frame-Options) | INFO; pode estar no proxy reverso, CDN ou ingress, invisível no repositório |
| Ausência de rate limit numa rota qualquer | Só é achado em rota sensível: login, recuperação de senha, pagamento, envio |
| Log de objeto de erro em catch | LOW; só sobe se logar senha, token ou sessão inteira |
| CORS permissivo em rota **sem** credencial e sem dado privado | Verificar se há cookie ou token antes |
| Upload sem validação de extensão, mas com validação de MIME e tamanho | Rebaixar; extensão sozinha não é a defesa principal |
| Comparação de segredo com `==` | LOW/MEDIUM (timing); só HIGH se for o único fator de autenticação |
| Desserialização de dado **próprio** e confiável | Só é achado com origem externa |

---

## Rebaixamento por contexto

| Situação | Ajuste |
|---|---|
| IDOR em recurso público por regra de negócio | INFO ou descartar |
| Segredo de teste (`test`, `sandbox`) em repositório privado | MEDIUM no máximo |
| Endpoint interno sem exposição externa comprovada | Rebaixar um nível e registrar a suposição |
| Framework já mitiga (CSRF por origem, escape automático de template) | Descartar salvo desativação explícita no código |
| Achado em branch ou arquivo morto (sem import, sem rota) | Descartar e mencionar como código morto |

---

## Excluir da varredura profunda

`node_modules/`, `target/`, `build/`, `dist/`, `.next/`, `coverage/`, código
gerado (cliente de ORM, stubs), lockfile linha a linha (usar o agregado do Step 1),
arquivos de teste — salvo quando o escopo pedido forem os testes.

---

## Registro obrigatório

Todo candidato descartado aqui vai para a seção **Descartados** do relatório, com
o motivo em uma linha. Isso torna o relatório auditável e evita que a mesma
discussão volte na próxima execução.
