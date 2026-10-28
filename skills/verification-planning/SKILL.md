---
name: verification-planning
description: >
  Antes de implementar, define o que precisa virar verdade, que evidência prova
  isso e o que poderia enganar a conclusão; depois de implementar, fecha o plano
  dizendo o que ficou provado e o que não. Use em mudança não trivial: feature
  que cruza sistemas, migration, integração externa, refatoração com risco de
  regressão, correção cuja causa não é óbvia. Para o ciclo de teste unitário em
  si, use tdd; para mudança mecânica, a verificação normal do projeto basta.
disable-model-invocation: true
argument-hint: "[mudança a planejar]"
---

# Verification Planning

Pergunta que esta skill responde **antes de escrever código**: como vou saber,
com evidência e não com impressão, que a mudança funciona?

"Os testes passaram" só responde se os testes observam o que mudou. Esta skill
existe para os casos em que isso não está garantido.

---

## Step 1 — Afirmações

Listar, em frases verificáveis:

- **O que passa a ser verdade.** "Agendamento no mesmo horário devolve 409."
- **O que precisa continuar verdade.** "Agendamento em horário livre continua
  devolvendo 201." Toda mudança tem pelo menos uma; é onde a regressão mora.
- **Onde a mudança cruza fronteira:** banco, fila, serviço externo, outro
  módulo, cliente que consome a resposta.
- **O que tornaria uma conclusão confiante errada:** teste que não exercita o
  caminho novo, ambiente local diferente de produção, dado de teste que não tem
  o caso real, cache, fuso, concorrência.

Afirmação que não dá para verificar está vaga demais. Reescrever.

---

## Step 2 — Caminho de evidência

Para cada afirmação, escolher como ela vai ser provada. Partir do que o sistema
permite controlar e observar, não da técnica favorita:

| Evidência | Serve quando |
|---|---|
| Teste unitário ou de integração do projeto | O comportamento é observável pela interface pública e o ambiente de teste reproduz o caso |
| Execução contra estado conhecido (seed, cópia local do banco, container) | Migration, consulta pesada, dado que o teste não tem |
| Chamada real ao sistema rodando (`curl`, cliente HTTP) | Contrato de resposta, middleware, configuração |
| Comparação antes/depois (saída, contagem, tempo) | Refatoração que não deveria mudar nada, ou mudança de desempenho |
| Leitura de log ou evento | Efeito assíncrono: fila, job, webhook |

Levantar pelo menos duas opções antes de escolher e ficar com a mais confiável
pelo custo. Registrar o limite da escolhida: o que ela **não** prova.

Uma afirmação, uma evidência dona dela. Duas evidências provando a mesma coisa
é desperdício; afirmação sem dona é buraco.

---

## Step 3 — Quando o sistema não deixa ver

Se nenhuma opção observa a afirmação diretamente, o caminho precisa de um apoio:
o mínimo que torna o estado controlável ou visível (script de seed, flag de log
detalhado, endpoint de diagnóstico, fixture).

Antes de construir, decidir e dizer ao usuário:

- **Temporário ou permanente.** Temporário sai antes do commit final.
  Permanente entra como código normal, com teste.
- **Se exige dependência nova, mudança estrutural ou superfície exposta em
  produção: perguntar antes.**

---

## Step 4 — Plano

Apresentar ao usuário antes de implementar:

```markdown
## Plano de verificação: <mudança>

| # | Afirmação | Evidência | Não prova |
|---|---|---|---|
| 1 | ... | ... | ... |

Apoio necessário: <nenhum | o quê, temporário ou permanente>
Verificação obrigatória do projeto: <typecheck, lint, testes>
```

Esperar confirmação. O plano é onde o usuário corrige uma afirmação errada,
antes de ela virar código.

---

## Step 5 — Fechar, depois de implementar

Seguir o plano e relatar cada afirmação como:

- **Provada:** com a evidência (saída do comando, nome do teste, número).
- **Parcial:** o que foi provado e o que ficou de fora.
- **Refutada:** o que a evidência mostrou. A implementação volta, não o plano.

Mais o que ficou sem verificar e por quê. Evidência obtida antes de uma mudança
posterior no mesmo código não vale: refazer.

Apoio temporário do Step 3 é removido aqui, e a remoção aparece no relatório.
