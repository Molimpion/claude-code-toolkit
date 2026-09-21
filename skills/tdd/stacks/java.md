# Stack — Java / Spring Boot

Carregado no Step 0 quando existe `pom.xml`, `build.gradle` ou `build.gradle.kts`.

---

## Comandos

| Build | Suíte inteira | Uma classe | Um método |
|---|---|---|---|
| Maven | `mvn -q test` | `mvn -q test -Dtest=PedidoServiceTest` | `mvn -q test -Dtest=PedidoServiceTest#naoAceitaValorNegativo` |
| Gradle | `./gradlew test` | `./gradlew test --tests '*PedidoServiceTest'` | `./gradlew test --tests '*PedidoServiceTest.naoAceitaValorNegativo'` |

**No loop, rodar sempre o teste isolado**, nunca a suíte inteira. A suíte inteira
só no Step 0 e no fim do trabalho. Feedback de 8 segundos mata o ciclo.

Detectar a lib de asserção antes de escrever: procurar `assertj` no manifesto. Se
existir, usar `assertThat(...)`; senão, `Assertions` do JUnit 5. Não introduzir
dependência nova para escrever um teste.

---

## Granularidade — a escada

O maior risco de TDD em Spring é o teste ficar lento e você abandonar o ciclo.
Subir a escada só quando o degrau anterior não conseguir observar o comportamento.

**Degrau 1 — POJO puro, sem contexto Spring (default).**
Instanciar o serviço com `new`, passando dependências no construtor. Sem
anotação nenhuma. Roda em milissegundos. É onde 80% da lógica de negócio deve ser
testada — e se não der para testar aqui, isso é sinal de desenho acoplado, não
motivo para subir de degrau.

```java
var service = new PedidoService(repositorioFake, relogioFixo);
```

**Degrau 2 — slice.** Quando o comportamento sob teste *é* a integração com uma
peça de infra: `@DataJpaTest` para mapeamento e query, `@WebMvcTest` para
serialização e status HTTP. Sobe só a fatia, não a aplicação.

**Degrau 3 — `@SpringBootTest`.** Só para fluxo ponta a ponta que atravessa
camadas de verdade. Poucos, e fora do loop rápido. Se o projeto já usa
Testcontainers, o banco real vive aqui.

**Nunca:** `@MockBean` nos seus próprios serviços. Isso é mockar colaborador
interno — o anti-padrão do `mocking.md` com anotação do Spring por cima.

---

## Fake vs mock

Preferir **fake** (implementação em memória da interface) a mock em degrau 1. Um
`Map<Long, Pedido>` implementando o repositório sobrevive a refatoração; um
Mockito com `verify(repo).save(any())` quebra na primeira mudança de assinatura e
não prova comportamento nenhum.

Mockito entra nas fronteiras que `mocking.md` autoriza: gateway de pagamento,
cliente HTTP externo, envio de e-mail.

Tempo e aleatoriedade: injetar `Clock` e `Random` no construtor, nunca chamar
`LocalDateTime.now()` direto dentro do serviço. Sem isso não existe teste
determinístico de nada que dependa de data.

---

## Nomes

Método de teste em português descrevendo capacidade, não implementação:
`naoPermitePedidoComValorNegativo()`, não `testValidarPedido()`.
Seguir o idioma que o projeto já usa no resto dos testes — não misturar.
