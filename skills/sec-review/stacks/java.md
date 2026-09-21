# Stack — Java / Spring Boot

Carregado no Step 0 quando existe `pom.xml`, `build.gradle` ou `build.gradle.kts`.

Escopo desta skill: **Spring Boot** (MVC e WebFlux). Outro framework JVM →
fallback do §1 e cobertura parcial no relatório.

Estrutura: **§1 detecção e versões**, **§2 invariantes**, **§3 controle de
acesso**, **§4 configuração**.

---

## §1 Detectar versões

```bash
mvn -q dependency:tree -Dscope=compile | head -60
# ou
./gradlew dependencies --configuration runtimeClasspath | head -60
grep -rn "spring-boot-starter" pom.xml build.gradle* 2>/dev/null
grep -E "<java.version>|sourceCompatibility|<release>" pom.xml build.gradle* 2>/dev/null
```

Registrar no relatório: versão do Spring Boot, do Spring Security (se presente),
do Java, e o ORM.

### Gates de versão

| Sinal | Consequência na auditoria |
|---|---|
| imports `javax.*` | Spring Boot 2 / Jakarta EE 8 — não propor API de Boot 3 |
| imports `jakarta.*` | Spring Boot 3+ |
| `WebSecurityConfigurerAdapter` presente | Spring Security 5. Removido na 6 — migrar para `SecurityFilterChain` como bean é **migração, não vulnerabilidade** |
| `authorizeRequests()` | Security 5; na 6 é `authorizeHttpRequests()`. Diferença de API |
| `@EnableGlobalMethodSecurity` | Security 5; na 6 é `@EnableMethodSecurity`, com `prePostEnabled` já ligado |
| **sem** `spring-boot-starter-security` | Não há camada de segurança do framework. Toda proteção precisa estar em filtro ou interceptor próprio — verificar se existe; ausência total é achado real, não configuração |

**Regra:** correção proposta tem que compilar na versão instalada. Nunca colar
snippet de outra major.

### CVE

Usar `dependency-check` ou `sonatype-scan` se estiverem configurados. Se não:
listar as versões e **declarar no relatório que a checagem de CVE não foi feita**.
Nunca inventar CVE nem afirmar de memória que uma versão é vulnerável.

---

## §2 Invariantes

### A02 — Cripto
`MessageDigest.getInstance("MD5"|"SHA-1")` para senha, ou hash sem salt →
`BCryptPasswordEncoder` / `Argon2PasswordEncoder`.
`new Random()` para token, convite ou reset → `SecureRandom`.
`TrustManager` que aceita qualquer certificado; verificador de hostname permissivo.
Comparação de segredo com `equals` em fluxo de auth → `MessageDigest.isEqual`.

### A03 — Injeção
- JPQL / HQL / SQL nativo concatenado: `"... where nome = '" + nome + "'"` →
  parâmetro nomeado ou posicional. `@Query(nativeQuery = true)` concatenado é o
  caso mais comum.
- `Statement` no lugar de `PreparedStatement`; `EntityManager.createQuery` com
  string montada.
- Ordenação dinâmica: `Sort` ou `ORDER BY` construído com string do usuário —
  parâmetro não protege identificador de coluna; exige allowlist.
- `Runtime.exec` / `ProcessBuilder` com input do usuário.
- `Path` / `File` com nome vindo de request sem `normalize()` e sem confinar ao
  diretório base.
- **XXE**: `DocumentBuilderFactory`, `SAXParserFactory`, `XMLInputFactory`,
  `TransformerFactory` sem desabilitar DTD e entidade externa.
- **SpEL**: expressão montada com string do usuário (inclusive dentro de
  `@Value` ou `@PreAuthorize` dinâmico).

### A04 / A07 — Auth e sessão
JWT: assinatura verificada de fato; algoritmo fixado; `none` recusado; expiração
presente; segredo em variável de ambiente, não em `application.properties`
versionado. Logout sem invalidação com token longo. Trava de tentativa em login e
recuperação de senha. Token de reset sem expiração ou reutilizável.

### A08 — Integridade
- **Desserialização**: `ObjectInputStream` sobre payload de request; Jackson com
  tipagem polimórfica (`enableDefaultTyping`, `@JsonTypeInfo` sobre `Object`)
  recebendo JSON externo; YAML com construtor irrestrito.
- **Mass assignment**: entidade JPA usada diretamente como `@RequestBody` —
  usuário envia campo que não deveria controlar (papel, saldo, id de dono). Usar
  DTO com campos explícitos.
- Upload sem limite, sem validar tipo real, com nome original no path.
- Webhook processado sem verificar assinatura.

### A09 — Logs
Logger recebendo entidade de usuário inteira, corpo de request de login, token,
ou exceção cuja mensagem carrega dado sensível.

### A10 — SSRF
`RestTemplate`, `WebClient`, `HttpClient`, `URL.openConnection` com URL vinda do
usuário sem allowlist de host.

---

## §3 Controle de acesso (A01)

O achado mais frequente: **id do path usado em `findById` sem comparar com o
usuário autenticado** — IDOR clássico de CRUD gerado.

```bash
grep -rn "@GetMapping\|@PostMapping\|@PutMapping\|@DeleteMapping\|@PatchMapping" src/main/java
grep -rn "SecurityFilterChain\|WebSecurityConfigurerAdapter\|@PreAuthorize\|@Secured\|@RolesAllowed" src/main/java
```

Verificar, na configuração de segurança:

- **Ordem dos matchers.** A primeira regra que casa vence. `anyRequest()`
  declarado antes de regra específica anula tudo que vem depois.
- `permitAll()` em prefixo amplo (`/api/**`, `/**`) — comparar com a intenção.
- Rota de admin sem prefixo protegido nem anotação.
- `@PreAuthorize` no controller, mas o **service público chamado por outro
  caminho**: listener de evento, `@Scheduled`, outro controller, endpoint interno.
  A anotação não acompanha a chamada interna.
- `@EnableMethodSecurity` ausente com `@PreAuthorize` espalhado — anotação inerte.
- Endpoint de listagem sem filtro por dono ou por tenant.
- Repositório exposto via Spring Data REST sem projeção nem restrição.
- Resposta devolvendo entidade completa em vez de DTO — vaza hash de senha,
  token de reset, campos internos. Checar também `@JsonIgnore` ausente.

**CSRF:** `csrf().disable()` é aceitável em API stateless que autentica por token
no header; é achado em aplicação que usa cookie de sessão. Determinar qual é o
caso antes de reportar.

---

## §4 Configuração (A05)

Verificar `application.properties`, `application.yml` e **todos** os
`application-*.yml` de perfil:

- credencial de banco ou segredo de assinatura literal em arquivo versionado
- Actuator sem proteção (`management.endpoints.web.exposure.include=*`) —
  `/env`, `/heapdump`, `/threaddump`, `/configprops` vazam segredo e memória
- `server.error.include-stacktrace=always` ou `include-message=always`
- `spring.h2.console.enabled=true` fora de desenvolvimento
- `spring.jpa.show-sql=true` e log de Hibernate em DEBUG em produção
- `spring.jpa.hibernate.ddl-auto=update` ou `create` em produção
- `@CrossOrigin` amplo, ou CORS `*` combinado com `allowCredentials`
- Swagger / OpenAPI aberto em produção sem proteção

```bash
grep -rn "MD5\|SHA-1\|new Random()" src/main/java
grep -rn "nativeQuery *= *true\|createQuery(\"" src/main/java
grep -rn "csrf()\.disable\|permitAll()\|anyRequest" src/main/java
grep -rn "Runtime.getRuntime\|ProcessBuilder\|ObjectInputStream" src/main/java
grep -rn "DocumentBuilderFactory\|SAXParserFactory\|XMLInputFactory" src/main/java
grep -rn "exposure.include\|show-sql\|include-stacktrace\|h2.console\|ddl-auto" src/main/resources
grep -rn "password\|secret\|jwt" src/main/resources/application*
```

São **pistas, não achados**. Confirmar contexto e passar pelo filtro do Step 5.
