---
name: quarkus-hexagonal
description: Scaffold, validate or extend a Quarkus project following Hexagonal Architecture (Ports & Adapters). Use when the user wants to create a new module, validate architecture compliance, add domain exceptions, add REST resources, or understand how the layers connect in Quarkus.
argument-hint: "[action: scaffold|validate|add-module|add-exception|add-resource] [name?]"
metadata:
  short-description: Quarkus Hexagonal Architecture scaffold & patterns
---

You are working on a Quarkus project that follows **Hexagonal Architecture (Ports & Adapters)**. Apply all patterns below without deviation. Read existing code before making changes.

---

## Design Principles & Patterns (non-negotiable)

Every decision in this skill is grounded in the following principles. Understand them — do not break them silently.

### SOLID

| Principle | How it applies here |
|-----------|-------------------|
| **S** — Single Responsibility | One class per use case (`CreateOrderService`, `GetOrderService`). Controllers only map HTTP ↔ domain. |
| **O** — Open/Closed | `DomainErrorCode` carries `httpStatus` — adding a new exception never modifies `DomainExceptionMapper`. |
| **L** — Liskov Substitution | Any `OrderRepository` implementation must honor the port contract — same behavior, different storage. |
| **I** — Interface Segregation | Ports are small, focused interfaces. `OrderRepository` is separate from `OrderEventPublisher`. |
| **D** — Dependency Inversion | Use cases depend on port interfaces, never on adapters. CDI injects the implementation at runtime. |

### GoF Patterns in use

| Pattern | Where |
|---------|-------|
| **Repository** | `OrderRepository` port + `OrderPanacheAdapter` — isolates persistence from domain |
| **Adapter** | Infrastructure adapters implement domain ports — the classic Adapter pattern |
| **Factory Method** | `Order.create(...)` — static factory validates invariants before construction |
| **Strategy** | Swappable adapters per port — e.g. mock vs real `OrderRepository` in tests |
| **Observer / Domain Events** | `OrderCreatedEvent` published via `OrderEventPublisher` port |
| **Template Method** | `DomainException` defines the structure; subclasses fill in message + code |
| **Null Object** | `Optional<T>` from outbound ports — never return `null` |

### Clean Code rules

- **Naming**: classes are nouns (`Order`, `CreateOrderService`), methods are verbs (`execute`, `save`, `findById`)
- **Use case method**: always named `execute(Request): Result` — no ambiguity
- **Function size**: use case `execute()` orchestrates — no more than 10-15 lines; business logic lives in the entity
- **No magic numbers**: all constants in `DomainErrorCode` or `@ConfigMapping` interfaces
- **No comments for obvious code**: self-documenting names over comments; comments only for non-obvious decisions

### Request Pipeline (imperative)

Every HTTP request flows through exactly these layers — no shortcuts:

```
HTTP Request
    │
    ▼
REST Resource          ← validates input (@Valid), maps to domain DTO
    │
    ▼
Use Case (Service)     ← orchestrates: validate business rules, call ports
    │
    ├──▶ Outbound Port ──▶ Persistence Adapter  ← DB
    │
    └──▶ Outbound Port ──▶ Event Adapter        ← Kafka / messaging
    │
    ▼
REST Resource          ← maps domain result to response DTO
    │
    ▼
HTTP Response
    │
    ▼ (on exception)
DomainExceptionMapper  ← maps DomainException → JSON error response
UnexpectedExceptionMapper ← catches everything else
```

**Rules:**
- The pipeline direction is one-way: infrastructure → application → domain — never reverse
- Use cases are the only layer that coordinates multiple ports
- REST resources never call persistence adapters directly
- Domain objects never call ports

---

## 0. Project Scaffolding

### Create the project

```bash
quarkus create app com.comiagro:my-service \
  --extension=resteasy-jackson,\
hibernate-orm-panache,\
jdbc-postgresql,\
smallrye-openapi,\
hibernate-validator,\
quarkus-junit5,\
rest-assured \
  --no-code
```

Or with Maven directly:

```bash
mvn io.quarkus.platform:quarkus-maven-plugin:3.9.5:create \
  -DprojectGroupId=com.comiagro \
  -DprojectArtifactId=my-service \
  -Dextensions="resteasy-jackson,hibernate-orm-panache,jdbc-postgresql,\
smallrye-openapi,hibernate-validator" \
  -DnoCode
```

### Required extensions

| Extension | Purpose |
|-----------|---------|
| `resteasy-jackson` | JAX-RS REST resources + JSON serialization |
| `hibernate-orm-panache` | JPA persistence with Panache repository pattern |
| `smallrye-openapi` | OpenAPI / Swagger UI |
| `hibernate-validator` | Bean Validation (`@Valid`, `@NotNull`, etc.) |

**Database driver — choose one:**

| Database | Extension | JDBC URL format |
|----------|-----------|----------------|
| PostgreSQL | `jdbc-postgresql` | `jdbc:postgresql://{host}:5432/{db}` |
| MySQL | `jdbc-mysql` | `jdbc:mysql://{host}:3306/{db}` |
| MariaDB | `jdbc-mariadb` | `jdbc:mariadb://{host}:3306/{db}` |
| Microsoft SQL Server | `jdbc-mssql` | `jdbc:sqlserver://{host}:1433;databaseName={db}` |
| Oracle | `jdbc-oracle` | `jdbc:oracle:thin:@{host}:1521:{db}` |
| H2 (dev/test only) | `jdbc-h2` | `jdbc:h2:mem:testdb;DB_CLOSE_DELAY=-1` |
| MongoDB | `mongodb-panache` | `mongodb://{host}:27017` |

> Dev Services auto-starts the chosen database in dev/test mode — no local installation needed for PostgreSQL, MySQL, MariaDB, MongoDB.

### Add extensions to an existing project

```bash
quarkus ext add smallrye-openapi
quarkus ext add hibernate-validator
```

### Delete generated boilerplate

After creation, remove the generated example files and create the hexagonal structure:

```bash
rm -rf src/main/java/com/comiagro/myservice
mkdir -p src/main/java/com/comiagro/myservice/{domain/{model,dto,exception,port/{inbound,outbound}},application/service,infrastructure/{adapter/{rest,persistence},exception,config}}
```

### Minimum `application.properties`

```properties
# ── Datasource ──────────────────────────────────────────────────────────
# Choose the db-kind that matches your driver extension:
#   postgresql | mysql | mariadb | mssql | oracle | h2 | mongodb
quarkus.datasource.db-kind=postgresql

quarkus.datasource.username=${DB_USER:app}
quarkus.datasource.password=${DB_PASS:secret}
quarkus.datasource.jdbc.url=${DB_URL:jdbc:postgresql://localhost:5432/appdb}

# ── Hibernate ────────────────────────────────────────────────────────────
# 'validate' in prod, 'drop-and-create' in dev (Flyway owns schema in prod)
quarkus.hibernate-orm.database.generation=${DB_GENERATION:validate}
quarkus.hibernate-orm.log.sql=false

# ── OpenAPI ──────────────────────────────────────────────────────────────
quarkus.swagger-ui.always-include=true
quarkus.smallrye-openapi.info-title=${quarkus.application.name}
quarkus.smallrye-openapi.info-version=1.0.0
```

**Profile overrides by database:**

```properties
# PostgreSQL (default)
%dev.quarkus.datasource.jdbc.url=jdbc:postgresql://localhost:5432/appdb

# MySQL
# %dev.quarkus.datasource.db-kind=mysql
# %dev.quarkus.datasource.jdbc.url=jdbc:mysql://localhost:3306/appdb

# MariaDB
# %dev.quarkus.datasource.db-kind=mariadb
# %dev.quarkus.datasource.jdbc.url=jdbc:mariadb://localhost:3306/appdb

# SQL Server
# %dev.quarkus.datasource.db-kind=mssql
# %dev.quarkus.datasource.jdbc.url=jdbc:sqlserver://localhost:1433;databaseName=appdb

# H2 in-memory (dev/test only — no Dev Services needed)
# %dev.quarkus.datasource.db-kind=h2
# %dev.quarkus.datasource.jdbc.url=jdbc:h2:mem:testdb;DB_CLOSE_DELAY=-1
# %dev.quarkus.hibernate-orm.database.generation=drop-and-create

# MongoDB (uses mongodb-panache, not jdbc)
# %dev.quarkus.mongodb.connection-string=mongodb://localhost:27017
```

### Dev mode

```bash
quarkus dev   # starts with Dev Services (auto Postgres container)
```

---

## Directory Structure

```
src/main/java/com/comiagro/app/
├── domain/                          # Inner hexagon — ZERO framework dependencies
│   ├── model/                       # Domain entities and value objects (plain Java)
│   ├── dto/                         # Input objects passed between layers
│   ├── exception/                   # Domain exceptions (no Quarkus/Jakarta imports)
│   │   ├── DomainException.java     # Abstract base with errorCode field
│   │   ├── DomainErrorCode.java     # Enum with COMI-{HTTP_FAMILY}{SEQ} format
│   │   └── *Exception.java
│   └── port/
│       ├── inbound/                 # Use case interfaces
│       └── outbound/                # Infrastructure interfaces
├── application/                     # Use case implementations
│   └── service/                     # Only imports from domain — never from infrastructure
└── infrastructure/                  # Outer hexagon — Quarkus, JPA, REST, etc.
    ├── adapter/
    │   ├── rest/                    # Inbound: JAX-RS resources + request/response DTOs
    │   └── persistence/             # Outbound: adapters implementing domain ports
    ├── exception/                   # ExceptionMappers (DomainExceptionMapper.java)
    └── config/                      # CDI producers / application configuration
```

---

## Dependency Rule (never violate)

```
infrastructure  →  application  →  domain
                        ↑
             implements ports at runtime
```

- `domain` imports nothing from `application` or `infrastructure`
- `application` imports nothing from `infrastructure`
- `infrastructure` imports everything it needs

---

## 1. Port Definition Pattern

Ports are plain Java interfaces. Qualifiers are defined in `infrastructure/config/` and used for CDI injection.

```java
// src/main/java/com/comiagro/app/domain/port/inbound/CreateOrderUseCase.java
package com.comiagro.app.domain.port.inbound;

import com.comiagro.app.domain.dto.OrderRequest;
import com.comiagro.app.domain.model.Order;

public interface CreateOrderUseCase {
    Order execute(OrderRequest request);
}
```

```java
// src/main/java/com/comiagro/app/domain/port/outbound/OrderRepository.java
package com.comiagro.app.domain.port.outbound;

import com.comiagro.app.domain.model.Order;
import java.util.Optional;

public interface OrderRepository {
    Order save(Order order);
    Optional<Order> findById(Long id);
}
```

---

## 2. CDI Qualifier Pattern

Use a dedicated qualifier annotation per port to enable CDI injection without ambiguity.

```java
// src/main/java/com/comiagro/app/infrastructure/config/qualifier/PanacheOrderRepo.java
package com.comiagro.app.infrastructure.config.qualifier;

import jakarta.inject.Qualifier;
import java.lang.annotation.*;

@Qualifier
@Retention(RetentionPolicy.RUNTIME)
@Target({ElementType.FIELD, ElementType.METHOD, ElementType.PARAMETER, ElementType.TYPE})
public @interface PanacheOrderRepo {}
```

> When only one implementation exists per port, `@ApplicationScoped` alone is sufficient — Quarkus resolves it unambiguously. Add a qualifier only when multiple implementations coexist.

---

## 3. Application Use Case Pattern

Use cases implement inbound ports and inject outbound ports. Never import REST, JPA, or any Quarkus-specific class.

```java
// src/main/java/com/comiagro/app/application/service/CreateOrderService.java
package com.comiagro.app.application.service;

import com.comiagro.app.domain.dto.OrderRequest;
import com.comiagro.app.domain.exception.OrderNotFoundException;
import com.comiagro.app.domain.model.Order;
import com.comiagro.app.domain.port.inbound.CreateOrderUseCase;
import com.comiagro.app.domain.port.outbound.OrderRepository;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;

@ApplicationScoped
public class CreateOrderService implements CreateOrderUseCase {

    @Inject
    OrderRepository orderRepository;     // single implementation — no qualifier needed

    @Override
    public Order execute(OrderRequest request) {
        // business logic only — no HTTP, no JPA, no framework concerns
        Order order = new Order(request.customerId(), request.items());
        return orderRepository.save(order);
    }
}
```

---

## 4. Domain Exception Pattern

El **HTTP status vive en `DomainErrorCode`** — el mapper nunca necesita cambiar cuando se agrega una nueva excepción (Open/Closed Principle).

```java
// src/main/java/com/comiagro/app/domain/exception/DomainErrorCode.java
package com.comiagro.app.domain.exception;

public enum DomainErrorCode {
    // Format: COMI-{HTTP_FAMILY}{SEQUENTIAL}
    INVALID_INPUT("COMI-4001", 400),
    NOT_FOUND    ("COMI-4041", 404),
    CONFLICT     ("COMI-4091", 409),
    UNPROCESSABLE("COMI-4221", 422),
    UNEXPECTED   ("COMI-5001", 500);

    public final String code;
    public final int    httpStatus;

    DomainErrorCode(String code, int httpStatus) {
        this.code       = code;
        this.httpStatus = httpStatus;
    }
}
```

```java
// src/main/java/com/comiagro/app/domain/exception/DomainException.java
package com.comiagro.app.domain.exception;

public abstract class DomainException extends RuntimeException {
    public final DomainErrorCode errorCode;

    protected DomainException(String message, DomainErrorCode errorCode) {
        super(message);
        this.errorCode = errorCode;
    }
}
```

```java
// src/main/java/com/comiagro/app/domain/exception/OrderNotFoundException.java
package com.comiagro.app.domain.exception;

public class OrderNotFoundException extends DomainException {
    public OrderNotFoundException(Long id) {
        super("Order not found: " + id, DomainErrorCode.NOT_FOUND);
    }
}
```

**Checklist when adding a new exception:**
1. Add a new entry to `DomainErrorCode` with its `httpStatus`
2. Create `domain/exception/<Name>Exception.java`
3. ~~Add the `instanceof` mapping~~ — nothing else to change in the mapper

---

## 5. Global Exception Handling

Two mappers registered via `@Provider` — Quarkus discovers them automatically.

```
@Provider DomainExceptionMapper      ← catches all DomainException subtypes
@Provider UnexpectedExceptionMapper  ← catches everything else (last resort)
```

`DomainExceptionMapper` is **closed for modification**: it reads the HTTP status directly from `errorCode.httpStatus`. Adding a new exception never requires touching this class.

```java
// src/main/java/com/comiagro/app/infrastructure/exception/DomainExceptionMapper.java
package com.comiagro.app.infrastructure.exception;

import com.comiagro.app.domain.exception.DomainException;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import jakarta.ws.rs.ext.ExceptionMapper;
import jakarta.ws.rs.ext.Provider;
import org.jboss.logging.Logger;

@Provider
public class DomainExceptionMapper implements ExceptionMapper<DomainException> {

    private static final Logger LOG = Logger.getLogger(DomainExceptionMapper.class);

    @Override
    public Response toResponse(DomainException ex) {
        int status = ex.errorCode.httpStatus;   // ← no instanceof chain
        LOG.warnf("[%s] %s: %s", ex.errorCode.code, ex.getClass().getSimpleName(), ex.getMessage());
        return Response.status(status)
                .type(MediaType.APPLICATION_JSON)
                .entity(new ErrorResponse(status, ex.errorCode.code,
                        ex.getClass().getSimpleName(), ex.getMessage()))
                .build();
    }
}
```

```java
// src/main/java/com/comiagro/app/infrastructure/exception/UnexpectedExceptionMapper.java
@Provider
public class UnexpectedExceptionMapper implements ExceptionMapper<Exception> {

    private static final Logger LOG = Logger.getLogger(UnexpectedExceptionMapper.class);

    @Override
    public Response toResponse(Exception ex) {
        LOG.errorf(ex, "[%s] Unhandled exception", DomainErrorCode.UNEXPECTED.code);
        return Response.status(500)
                .type(MediaType.APPLICATION_JSON)
                .entity(new ErrorResponse(500, DomainErrorCode.UNEXPECTED.code,
                        "InternalServerError", "An unexpected error occurred"))
                .build();
    }
}
```

```java
// src/main/java/com/comiagro/app/infrastructure/exception/ErrorResponse.java
public record ErrorResponse(int statusCode, String errorCode, String error, String message) {}
```

> **Why two mappers?** JAX-RS resolves the most specific mapper first. `DomainExceptionMapper` handles all known business errors. `UnexpectedExceptionMapper` is the safety net for anything else (NPE, DB connection lost, etc.) — it intentionally hides the real message from the client.

---

## 6. REST Resource Pattern

Resources inject inbound port interfaces directly. Map HTTP DTOs to domain objects here.

```java
// src/main/java/com/comiagro/app/infrastructure/adapter/rest/OrderResource.java
package com.comiagro.app.infrastructure.adapter.rest;

import com.comiagro.app.domain.model.Order;
import com.comiagro.app.domain.port.inbound.CreateOrderUseCase;
import com.comiagro.app.infrastructure.adapter.rest.dto.CreateOrderRequest;
import jakarta.inject.Inject;
import jakarta.validation.Valid;
import jakarta.ws.rs.*;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import org.eclipse.microprofile.openapi.annotations.tags.Tag;

@Path("/orders")
@Produces(MediaType.APPLICATION_JSON)
@Consumes(MediaType.APPLICATION_JSON)
@Tag(name = "Orders")
public class OrderResource {

    @Inject
    CreateOrderUseCase createOrderUseCase;

    @POST
    public Response create(@Valid CreateOrderRequest request) {
        Order order = createOrderUseCase.execute(request.toDomain());
        return Response.status(Response.Status.CREATED).entity(order).build();
    }
}
```

---

## 7. Persistence Adapter Pattern (Panache)

```java
// src/main/java/com/comiagro/app/infrastructure/adapter/persistence/OrderPanacheAdapter.java
package com.comiagro.app.infrastructure.adapter.persistence;

import com.comiagro.app.domain.model.Order;
import com.comiagro.app.domain.port.outbound.OrderRepository;
import io.quarkus.hibernate.orm.panache.PanacheRepository;
import jakarta.enterprise.context.ApplicationScoped;

import java.util.Optional;

@ApplicationScoped
public class OrderPanacheAdapter implements OrderRepository, PanacheRepository<OrderEntity> {

    @Override
    public Order save(Order order) {
        OrderEntity entity = OrderMapper.toEntity(order);
        persist(entity);
        return OrderMapper.toDomain(entity);
    }

    @Override
    public Optional<Order> findById(Long id) {
        return find("id", id).firstResultOptional().map(OrderMapper::toDomain);
    }
}
```

> Keep `OrderEntity` (JPA `@Entity`) and `OrderMapper` in the `persistence/` package — they are infrastructure details the domain must never see.

---

## 8. application.properties Convention

```properties
# Datasource
quarkus.datasource.db-kind=postgresql
quarkus.datasource.username=${DB_USER:app}
quarkus.datasource.password=${DB_PASS:secret}
quarkus.datasource.jdbc.url=jdbc:postgresql://${DB_HOST:localhost}:5432/${DB_NAME:appdb}

# Hibernate
quarkus.hibernate-orm.database.generation=validate
quarkus.hibernate-orm.log.sql=false

# OpenAPI / Swagger
quarkus.swagger-ui.always-include=true
quarkus.smallrye-openapi.info-title=App API
quarkus.smallrye-openapi.info-version=1.0.0
```

---

## Error Response Shape

All errors return a consistent JSON structure:
```json
{
  "statusCode": 404,
  "errorCode": "COMI-4041",
  "error": "OrderNotFoundException",
  "message": "Order not found: 42"
}
```

---

## 9. Testing Strategy

Three layers — each with its own scope and tools.

```
src/test/java/com/comiagro/app/
├── domain/                          # Pure unit tests — no Quarkus, no mocks framework needed
│   ├── model/                       # Entity invariants and factory methods
│   └── exception/                   # Exception messages and error codes
├── application/                     # Use case unit tests — mock outbound ports with Mockito
│   └── service/
└── infrastructure/                  # Integration tests — @QuarkusTest + real DB (Dev Services)
    ├── rest/                        # REST endpoints via RestAssured
    └── persistence/                 # Adapter queries against real DB
```

### 9.1 Domain Unit Tests (no annotations needed)

```java
// src/test/java/com/comiagro/app/domain/model/OrderTest.java
package com.comiagro.app.domain.model;

import com.comiagro.app.domain.exception.DomainException;
import org.junit.jupiter.api.Test;
import static org.assertj.core.api.Assertions.*;

class OrderTest {

    @Test
    void create_fails_when_items_are_empty() {
        assertThatThrownBy(() -> Order.create("customer-1", List.of()))
                .isInstanceOf(DomainException.class)
                .hasMessageContaining("items cannot be empty");
    }

    @Test
    void confirm_transitions_status_to_confirmed() {
        Order order = Order.create("customer-1", List.of(new Item("p1", 1)));
        order.confirm();
        assertThat(order.getStatus()).isEqualTo(OrderStatus.CONFIRMED);
    }

    @Test
    void confirm_fails_when_already_confirmed() {
        Order order = Order.create("customer-1", List.of(new Item("p1", 1)));
        order.confirm();
        assertThatThrownBy(order::confirm)
                .isInstanceOf(DomainException.class);
    }
}
```

### 9.2 Use Case Unit Tests (Mockito — no Quarkus context)

```java
// src/test/java/com/comiagro/app/application/service/CreateOrderServiceTest.java
package com.comiagro.app.application.service;

import com.comiagro.app.domain.dto.OrderRequest;
import com.comiagro.app.domain.exception.OrderNotFoundException;
import com.comiagro.app.domain.port.outbound.OrderRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.MockitoAnnotations;
import static org.assertj.core.api.Assertions.*;
import static org.mockito.Mockito.*;

class CreateOrderServiceTest {

    @Mock  OrderRepository repository;
    @InjectMocks CreateOrderService service;

    @BeforeEach
    void setUp() { MockitoAnnotations.openMocks(this); }

    @Test
    void execute_saves_and_returns_order() {
        var request = new OrderRequest("customer-1", List.of(new ItemDTO("p1", 1)));
        var saved   = Order.create("customer-1", List.of(new Item("p1", 1)));
        when(repository.save(any())).thenReturn(saved);

        Order result = service.execute(request);

        assertThat(result).isNotNull();
        verify(repository, times(1)).save(any());
    }

    @Test
    void execute_throws_when_repository_fails() {
        when(repository.save(any())).thenThrow(new RuntimeException("DB down"));

        assertThatThrownBy(() -> service.execute(new OrderRequest("c1", List.of(new ItemDTO("p1", 1)))))
                .isInstanceOf(RuntimeException.class);
    }
}
```

### 9.3 REST Integration Tests (@QuarkusTest + RestAssured)

```java
// src/test/java/com/comiagro/app/infrastructure/rest/OrderResourceTest.java
package com.comiagro.app.infrastructure.rest;

import com.comiagro.app.domain.port.inbound.CreateOrderUseCase;
import io.quarkus.test.InjectMock;
import io.quarkus.test.junit.QuarkusTest;
import io.restassured.http.ContentType;
import org.junit.jupiter.api.Test;
import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;

@QuarkusTest
class OrderResourceTest {

    @InjectMock
    CreateOrderUseCase createOrderUseCase;  // replaces the real CDI bean

    @Test
    void post_order_returns_201() {
        when(createOrderUseCase.execute(any()))
                .thenReturn(new Order(1L, "customer-1", OrderStatus.PENDING));

        given()
            .contentType(ContentType.JSON)
            .body("""
                { "customerId": "customer-1",
                  "items": [{ "productId": "p1", "quantity": 1 }] }
                """)
        .when()
            .post("/orders")
        .then()
            .statusCode(201)
            .body("id", notNullValue())
            .body("status", equalTo("PENDING"));
    }

    @Test
    void post_order_returns_404_on_not_found() {
        when(createOrderUseCase.execute(any()))
                .thenThrow(new OrderNotFoundException(99L));

        given()
            .contentType(ContentType.JSON)
            .body("""
                { "customerId": "c1", "items": [{ "productId": "missing", "quantity": 1 }] }
                """)
        .when()
            .post("/orders")
        .then()
            .statusCode(404)
            .body("errorCode", equalTo("COMI-4041"));
    }
}
```

### 9.4 Persistence Integration Tests (@QuarkusTest + Dev Services)

```java
// src/test/java/com/comiagro/app/infrastructure/persistence/OrderPanacheAdapterTest.java
@QuarkusTest
@TestTransaction  // rolls back after each test — no cleanup needed
class OrderPanacheAdapterTest {

    @Inject OrderPanacheAdapter adapter;

    @Test
    void save_and_findById_roundtrip() {
        Order order = Order.create("customer-1", List.of(new Item("p1", 1)));
        Order saved = adapter.save(order);

        assertThat(saved.getId()).isNotNull();

        Optional<Order> found = adapter.findById(saved.getId());
        assertThat(found).isPresent()
                         .get()
                         .extracting(Order::getCustomerId)
                         .isEqualTo("customer-1");
    }
}
```

> **Dev Services**: Quarkus auto-starts a Postgres container for tests — no `application.properties` changes needed for the test profile.

### 9.5 Coverage Requirement

**Minimum coverage: 80%** — enforced via JaCoCo in the build.

```xml
<!-- pom.xml -->
<plugin>
  <groupId>org.jacoco</groupId>
  <artifactId>jacoco-maven-plugin</artifactId>
  <executions>
    <execution>
      <id>prepare-agent</id>
      <goals><goal>prepare-agent</goal></goals>
    </execution>
    <execution>
      <id>check</id>
      <phase>verify</phase>
      <goals><goal>check</goal></goals>
      <configuration>
        <rules>
          <rule>
            <element>BUNDLE</element>
            <limits>
              <limit>
                <counter>LINE</counter>
                <value>COVEREDRATIO</value>
                <minimum>0.80</minimum>
              </limit>
              <limit>
                <counter>BRANCH</counter>
                <value>COVEREDRATIO</value>
                <minimum>0.80</minimum>
              </limit>
            </limits>
          </rule>
        </rules>
        <!-- Exclude infrastructure wiring and generated code -->
        <excludes>
          <exclude>**/infrastructure/config/**</exclude>
          <exclude>**/infrastructure/adapter/persistence/*Entity.class</exclude>
          <exclude>**/infrastructure/adapter/persistence/*Mapper.class</exclude>
        </excludes>
      </configuration>
    </execution>
  </executions>
</plugin>
```

Run coverage report:
```bash
./mvnw verify              # fails if coverage < 80%
./mvnw jacoco:report       # generates target/site/jacoco/index.html
```

**Coverage targets by layer:**

| Layer | Target | Why |
|-------|--------|-----|
| `domain/model` | ≥ 90% | Pure logic — easiest to test |
| `domain/exception` | ≥ 90% | Simple constructors |
| `application/service` | ≥ 85% | Core business flow |
| `infrastructure/adapter/rest` | ≥ 80% | Via `@QuarkusTest` |
| `infrastructure/exception` | ≥ 80% | Via REST integration tests |
| `infrastructure/config` | excluded | CDI wiring, not testable in isolation |

### 9.7 Testing Rules

- **Domain tests** → plain JUnit 5 + AssertJ. Zero annotations, zero mocks.
- **Use case tests** → Mockito only (`@Mock` + `@InjectMocks`). No `@QuarkusTest`.
- **REST tests** → `@QuarkusTest` + `@InjectMock` on the inbound port. Never mock infrastructure directly.
- **Persistence tests** → `@QuarkusTest` + `@TestTransaction`. Let Dev Services provide the DB.
- **Never** test an `ExceptionMapper` in isolation — test it through the REST layer.
- **Never** assert on `OrderEntity` fields from a use case test — that is an infrastructure detail.

---

## 10. Value Objects (DDD)

Value Objects encapsulan validación y semántica — evitan primitivos desnudos (`String email`, `Long id`).

```java
// domain/model/vo/Email.java
package com.comiagro.app.domain.model.vo;

import com.comiagro.app.domain.exception.DomainErrorCode;
import com.comiagro.app.domain.exception.DomainException;

public record Email(String value) {
    public Email {
        if (value == null || !value.matches("^[\\w.+-]+@[\\w-]+\\.[\\w.]+$")) {
            throw new DomainException("Invalid email: " + value, DomainErrorCode.INVALID_INPUT);
        }
        value = value.toLowerCase();
    }
}
```

```java
// domain/model/vo/Money.java
public record Money(BigDecimal amount, String currency) {
    public Money {
        if (amount == null || amount.compareTo(BigDecimal.ZERO) < 0) {
            throw new DomainException("Amount must be non-negative", DomainErrorCode.INVALID_INPUT);
        }
        Objects.requireNonNull(currency, "Currency is required");
    }

    public Money add(Money other) {
        if (!this.currency.equals(other.currency)) {
            throw new DomainException("Cannot add different currencies", DomainErrorCode.INVALID_INPUT);
        }
        return new Money(this.amount.add(other.amount), this.currency);
    }
}
```

> **Rule**: if a primitive has validation rules or behavior, make it a Value Object. Use records for immutability.

---

## 11. Mapper Pattern

Mappers translate between layers. Keep them as static utility classes inside the infrastructure package that owns the translation.

```java
// infrastructure/adapter/persistence/OrderMapper.java
package com.comiagro.app.infrastructure.adapter.persistence;

final class OrderMapper {
    private OrderMapper() {}

    static OrderEntity toEntity(Order domain) {
        OrderEntity entity = new OrderEntity();
        entity.setCustomerId(domain.getCustomerId());
        entity.setStatus(domain.getStatus().name());
        return entity;
    }

    static Order toDomain(OrderEntity entity) {
        return Order.reconstitute(entity.getId(), entity.getCustomerId(),
                OrderStatus.valueOf(entity.getStatus()));
    }
}
```

```java
// infrastructure/adapter/rest/OrderResponseMapper.java
package com.comiagro.app.infrastructure.adapter.rest;

final class OrderResponseMapper {
    private OrderResponseMapper() {}

    static OrderResponse toResponse(Order domain) {
        return new OrderResponse(domain.getId(), domain.getCustomerId(),
                domain.getStatus().name(), domain.getCreatedAt());
    }
}
```

**Rules:**
- Mappers live in the **infrastructure** package that needs them — never in domain
- REST mappers: `domain → response DTO`; Persistence mappers: `domain ↔ entity`
- Use **MapStruct** only when mappings are many and complex; otherwise plain static methods

---

## 12. Logging Conventions

```java
// Use JBoss Logger — injected as a static field
private static final Logger LOG = Logger.getLogger(CreateOrderService.class);

// INFO  — significant business events
LOG.infof("Order created: id=%d customer=%s", order.getId(), order.getCustomerId());

// WARN  — domain exceptions (expected, recoverable)
LOG.warnf("[%s] %s: %s", ex.errorCode.code, ex.getClass().getSimpleName(), ex.getMessage());

// ERROR — unexpected exceptions (bugs, infra failures)
LOG.errorf(ex, "[%s] Unhandled exception in %s", DomainErrorCode.UNEXPECTED.code, getClass().getSimpleName());
```

**Rules:**
- Log at **WARN** for `DomainException` — it is expected business flow
- Log at **ERROR** only in `UnexpectedExceptionMapper` — never swallow stack traces
- Never log passwords, tokens, or PII
- Use parameterized messages (`%s`, `%d`) — never string concatenation in log calls

---

## 13. Health Checks

```xml
<!-- pom.xml -->
<dependency>
  <groupId>io.quarkus</groupId>
  <artifactId>quarkus-smallrye-health</artifactId>
</dependency>
```

```java
// infrastructure/health/DatabaseHealthCheck.java
package com.comiagro.app.infrastructure.health;

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import org.eclipse.microprofile.health.HealthCheck;
import org.eclipse.microprofile.health.HealthCheckResponse;
import org.eclipse.microprofile.health.Readiness;

@Readiness
@ApplicationScoped
public class DatabaseHealthCheck implements HealthCheck {

    @Inject
    javax.sql.DataSource dataSource;

    @Override
    public HealthCheckResponse call() {
        try (var conn = dataSource.getConnection()) {
            conn.isValid(1);
            return HealthCheckResponse.up("database");
        } catch (Exception e) {
            return HealthCheckResponse.down("database");
        }
    }
}
```

| Endpoint | Annotation | Purpose |
|----------|-----------|---------|
| `/q/health/live` | `@Liveness` | Is the process alive? (restart if down) |
| `/q/health/ready` | `@Readiness` | Is it ready to receive traffic? |
| `/q/health` | both | Combined |

---

## 14. Pagination Pattern

```java
// domain/dto/PageRequest.java
public record PageRequest(int page, int size) {
    public PageRequest {
        if (page < 0) throw new DomainException("Page must be >= 0", DomainErrorCode.INVALID_INPUT);
        if (size < 1 || size > 100) throw new DomainException("Size must be 1-100", DomainErrorCode.INVALID_INPUT);
    }
}

// domain/dto/PageResult.java
public record PageResult<T>(List<T> content, long totalElements, int totalPages, int page) {
    public static <T> PageResult<T> of(List<T> content, long total, PageRequest req) {
        int totalPages = (int) Math.ceil((double) total / req.size());
        return new PageResult<>(content, total, totalPages, req.page());
    }
}
```

```java
// domain/port/outbound/OrderRepository.java
public interface OrderRepository {
    Order save(Order order);
    Optional<Order> findById(Long id);
    PageResult<Order> findAll(PageRequest pageRequest);   // ← paginated query
}
```

```java
// infrastructure/adapter/persistence/OrderPanacheAdapter.java
@Override
public PageResult<Order> findAll(PageRequest req) {
    PanacheQuery<OrderEntity> query = findAll(Sort.by("createdAt").descending());
    query.page(req.page(), req.size());
    List<Order> content = query.list().stream().map(OrderMapper::toDomain).toList();
    long total = query.count();
    return PageResult.of(content, total, req);
}
```

```java
// infrastructure/adapter/rest/OrderResource.java
@GET
public PageResult<OrderResponse> list(
        @QueryParam("page") @DefaultValue("0") int page,
        @QueryParam("size") @DefaultValue("20") int size) {
    PageResult<Order> result = listOrdersUseCase.execute(new PageRequest(page, size));
    return new PageResult<>(
        result.content().stream().map(OrderResponseMapper::toResponse).toList(),
        result.totalElements(), result.totalPages(), result.page());
}
```

---

## 15. Security (JWT + @RolesAllowed)

```xml
<!-- pom.xml -->
<dependency>
  <groupId>io.quarkus</groupId>
  <artifactId>quarkus-smallrye-jwt</artifactId>
</dependency>
```

```properties
# application.properties
mp.jwt.verify.publickey.location=META-INF/resources/publicKey.pem
mp.jwt.verify.issuer=https://auth.comiagro.com
```

```java
// infrastructure/adapter/rest/OrderResource.java
import jakarta.annotation.security.RolesAllowed;
import org.eclipse.microprofile.jwt.JsonWebToken;

@Path("/orders")
@Authenticated                        // all endpoints require a valid token
public class OrderResource {

    @Inject JsonWebToken jwt;         // access claims if needed

    @POST
    @RolesAllowed("orders:write")     // fine-grained role check
    public Response create(@Valid CreateOrderRequest request) { ... }

    @GET
    @RolesAllowed({"orders:read", "admin"})
    public PageResult<OrderResponse> list(...) { ... }
}
```

**Rules:**
- `@Authenticated` at class level — deny unauthenticated by default
- `@RolesAllowed` at method level for fine-grained control
- Never put authorization logic in the domain or application layer
- Extract the subject/tenant from `JsonWebToken` in the REST layer and pass it as part of the domain request DTO

---

## 16. Observability

### Metrics (Micrometer)

```xml
<dependency>
  <groupId>io.quarkus</groupId>
  <artifactId>quarkus-micrometer-registry-prometheus</artifactId>
</dependency>
```

```java
// application/service/CreateOrderService.java
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.Timer;

@ApplicationScoped
public class CreateOrderService implements CreateOrderUseCase {

    @Inject MeterRegistry registry;

    @Override
    public Order execute(OrderRequest request) {
        return Timer.builder("order.create")
                .tag("status", "attempt")
                .register(registry)
                .record(() -> doExecute(request));
    }
}
```

### Distributed Tracing (OpenTelemetry)

```xml
<dependency>
  <groupId>io.quarkus</groupId>
  <artifactId>quarkus-opentelemetry</artifactId>
</dependency>
```

```properties
quarkus.otel.exporter.otlp.endpoint=http://jaeger:4317
quarkus.otel.service.name=${quarkus.application.name}
```

Quarkus auto-instruments JAX-RS, Hibernate, and reactive pipelines — no code changes needed for basic tracing.

---

## 17. Optional vs Exception — When to Use Each

| Scenario | Return |
|----------|--------|
| Query that may find nothing (expected) | `Optional<T>` |
| Query that MUST find a result (business invariant) | throw `NotFoundException` |
| Void operation that may not find the target | throw `NotFoundException` |

```java
// domain/port/outbound/OrderRepository.java
Optional<Order> findById(Long id);          // caller decides if absent is ok
List<Order> findByCustomer(String customerId); // empty list, never null

// application/service/GetOrderService.java
public Order execute(Long id) {
    return orderRepository.findById(id)
            .orElseThrow(() -> new OrderNotFoundException(id));  // ← business invariant
}
```

**Rules:**
- Outbound ports return `Optional<T>` — they don't know if absence is an error
- Use cases decide: if the business requires the entity to exist, they throw the exception
- Never return `null` from any port or service method

---

## 18. DB Migrations (Flyway)

```xml
<!-- pom.xml -->
<dependency>
  <groupId>io.quarkus</groupId>
  <artifactId>quarkus-flyway</artifactId>
</dependency>
```

```properties
# application.properties
quarkus.flyway.migrate-at-start=true
quarkus.flyway.locations=classpath:db/migration
quarkus.flyway.baseline-on-migrate=true
```

```
src/main/resources/db/migration/
├── V1__create_orders_table.sql
├── V2__add_order_status_index.sql
└── V3__add_customer_id_column.sql
```

```sql
-- V1__create_orders_table.sql
CREATE TABLE orders (
    id          BIGSERIAL PRIMARY KEY,
    customer_id VARCHAR(100) NOT NULL,
    status      VARCHAR(50)  NOT NULL DEFAULT 'PENDING',
    created_at  TIMESTAMP    NOT NULL DEFAULT NOW()
);
```

**Rules:**
- File name: `V{version}__{description}.sql` — version is integer, never reuse
- Never modify an existing migration — always add a new one
- In dev: `quarkus.hibernate-orm.database.generation=none` (Flyway owns the schema)
- In test: use `quarkus.flyway.clean-at-start=true` in `application-test.properties`

> **MongoDB**: Flyway is not applicable. Use schema evolution through Panache entity updates or a custom migration framework.

---

## 19. Config Management (@ConfigMapping)

```java
// infrastructure/config/AppConfig.java
package com.comiagro.app.infrastructure.config;

import io.smallrye.config.ConfigMapping;
import io.smallrye.config.WithDefault;

@ConfigMapping(prefix = "app")
public interface AppConfig {
    OrderConfig order();
    SecurityConfig security();

    interface OrderConfig {
        @WithDefault("100")
        int maxItemsPerOrder();
        @WithDefault("USD")
        String defaultCurrency();
    }

    interface SecurityConfig {
        String jwtIssuer();
        @WithDefault("3600")
        long tokenExpirationSeconds();
    }
}
```

```properties
# application.properties
app.order.max-items-per-order=50
app.order.default-currency=ARS
app.security.jwt-issuer=https://auth.comiagro.com

# Profile overrides — applied automatically by Quarkus
%dev.app.order.max-items-per-order=9999
%test.app.security.jwt-issuer=https://test.comiagro.com
%prod.app.security.jwt-issuer=${JWT_ISSUER}   # from env var in prod
```

```java
// Inject anywhere in infrastructure
@Inject AppConfig config;

int max = config.order().maxItemsPerOrder();
```

**Profile convention:**

| Profile | When active | Typical overrides |
|---------|------------|------------------|
| `dev` | `quarkus dev` | relaxed limits, mock services |
| `test` | `./mvnw test` | test JWT issuer, in-memory DB |
| `prod` | deployed artifact | all values from env vars / secrets |

---

## 20. Messaging / Kafka (SmallRye Reactive Messaging)

```xml
<dependency>
  <groupId>io.quarkus</groupId>
  <artifactId>quarkus-smallrye-reactive-messaging-kafka</artifactId>
</dependency>
```

### Domain Event (pure Java — no framework)

```java
// domain/model/event/OrderCreatedEvent.java
public record OrderCreatedEvent(Long orderId, String customerId, Instant occurredAt) {}
```

### Outbound Port for Events

```java
// domain/port/outbound/OrderEventPublisher.java
public interface OrderEventPublisher {
    void publish(OrderCreatedEvent event);
}
```

### Kafka Adapter

```java
// infrastructure/adapter/messaging/KafkaOrderEventAdapter.java
@ApplicationScoped
public class KafkaOrderEventAdapter implements OrderEventPublisher {

    @Channel("orders-out")
    MutinyEmitter<String> emitter;

    @Inject ObjectMapper objectMapper;

    @Override
    public void publish(OrderCreatedEvent event) {
        try {
            emitter.sendAndAwait(objectMapper.writeValueAsString(event));
        } catch (JsonProcessingException e) {
            throw new RuntimeException("Failed to serialize event", e);
        }
    }
}
```

### Consumer

```java
// infrastructure/adapter/messaging/OrderEventConsumer.java
@ApplicationScoped
public class OrderEventConsumer {

    private static final Logger LOG = Logger.getLogger(OrderEventConsumer.class);

    @Incoming("orders-in")
    public void consume(String payload) {
        LOG.infof("Received event: %s", payload);
        // deserialize + call use case
    }
}
```

```properties
# application.properties
mp.messaging.outgoing.orders-out.connector=smallrye-kafka
mp.messaging.outgoing.orders-out.topic=orders
mp.messaging.outgoing.orders-out.value.serializer=org.apache.kafka.common.serialization.StringSerializer

mp.messaging.incoming.orders-in.connector=smallrye-kafka
mp.messaging.incoming.orders-in.topic=orders
mp.messaging.incoming.orders-in.value.deserializer=org.apache.kafka.common.serialization.StringDeserializer
mp.messaging.incoming.orders-in.group.id=my-service

# Dev Services auto-starts Kafka — no broker needed locally
```

---

## 21. Resilience (SmallRye Fault Tolerance)

```xml
<dependency>
  <groupId>io.quarkus</groupId>
  <artifactId>quarkus-smallrye-fault-tolerance</artifactId>
</dependency>
```

Apply resilience annotations **only on infrastructure adapters** — never on domain or use case.

```java
// infrastructure/adapter/outbound/ExternalInventoryAdapter.java
@ApplicationScoped
public class ExternalInventoryAdapter implements InventoryPort {

    @Retry(maxRetries = 3, delay = 500, delayUnit = ChronoUnit.MILLIS)
    @Timeout(value = 2, unit = ChronoUnit.SECONDS)
    @CircuitBreaker(requestVolumeThreshold = 10, failureRatio = 0.5, delay = 5, delayUnit = ChronoUnit.SECONDS)
    @Fallback(fallbackMethod = "fallbackHasStock")
    @Override
    public boolean hasStock(String productId) {
        return externalApi.checkStock(productId);
    }

    boolean fallbackHasStock(String productId) {
        LOG.warnf("Fallback triggered for product: %s", productId);
        return false;  // safe default — deny instead of assuming stock
    }
}
```

| Annotation | Purpose |
|-----------|---------|
| `@Retry` | Retry on transient failures |
| `@Timeout` | Fail fast if response is too slow |
| `@CircuitBreaker` | Stop calling failing services |
| `@Fallback` | Safe default when all else fails |
| `@Bulkhead` | Limit concurrent calls |

**Rules:**
- Fallback method must have the same signature as the guarded method
- Never apply `@Retry` on non-idempotent operations without idempotency keys
- Circuit breaker state is per-instance — use `@Singleton` for shared state

---

## 22. Containerization

### JVM mode (Dockerfile.jvm — generated by Quarkus)

```dockerfile
FROM registry.access.redhat.com/ubi8/openjdk-21:1.20
ENV LANGUAGE='en_US:en'
COPY --chown=185 target/quarkus-app/lib/ /deployments/lib/
COPY --chown=185 target/quarkus-app/*.jar /deployments/
COPY --chown=185 target/quarkus-app/app/ /deployments/app/
COPY --chown=185 target/quarkus-app/quarkus/ /deployments/quarkus/
EXPOSE 8080
USER 185
ENV JAVA_OPTS_APPEND="-Dquarkus.http.host=0.0.0.0 -Djava.util.logging.manager=org.jboss.logmanager.LogManager"
ENTRYPOINT [ "/opt/jboss/container/java/run/run-java.sh" ]
```

### Native mode

```dockerfile
FROM quay.io/quarkus/quarkus-micro-image:2.0
WORKDIR /work/
RUN chown 1001 /work && chmod "g+rwX" /work && chown 1001:root /work
COPY --chown=1001:root target/*-runner /work/application
EXPOSE 8080
USER 1001
CMD ["./application", "-Dquarkus.http.host=0.0.0.0"]
```

```bash
# Build JVM image
./mvnw package
docker build -f src/main/docker/Dockerfile.jvm -t comiagro/my-service:latest .

# Build native image (requires GraalVM or Docker)
./mvnw package -Pnative -Dquarkus.native.container-build=true
docker build -f src/main/docker/Dockerfile.native -t comiagro/my-service:native .
```

```properties
# Useful container properties
quarkus.http.host=0.0.0.0
quarkus.http.port=8080
quarkus.log.console.json=true          # structured JSON logs in prod
quarkus.log.console.json=false         # human-readable in dev (%dev prefix)
%prod.quarkus.log.console.json=true
```

---

## 23. OpenAPI Annotations

```java
// infrastructure/adapter/rest/OrderResource.java
import org.eclipse.microprofile.openapi.annotations.Operation;
import org.eclipse.microprofile.openapi.annotations.responses.APIResponse;
import org.eclipse.microprofile.openapi.annotations.tags.Tag;
import org.eclipse.microprofile.openapi.annotations.media.Content;
import org.eclipse.microprofile.openapi.annotations.media.Schema;

@Path("/orders")
@Tag(name = "Orders", description = "Order management operations")
public class OrderResource {

    @POST
    @Operation(summary = "Create a new order", description = "Creates an order for the given customer")
    @APIResponse(responseCode = "201", description = "Order created",
        content = @Content(schema = @Schema(implementation = OrderResponse.class)))
    @APIResponse(responseCode = "400", description = "Invalid input",
        content = @Content(schema = @Schema(implementation = ErrorResponse.class)))
    @APIResponse(responseCode = "409", description = "Insufficient stock",
        content = @Content(schema = @Schema(implementation = ErrorResponse.class)))
    public Response create(@Valid CreateOrderRequest request) { ... }

    @GET
    @Operation(summary = "List orders", description = "Returns paginated list of orders")
    @APIResponse(responseCode = "200", description = "OK",
        content = @Content(schema = @Schema(implementation = OrderResponse.class)))
    public PageResult<OrderResponse> list(
            @Parameter(description = "Page number, 0-based") @QueryParam("page") @DefaultValue("0") int page,
            @Parameter(description = "Page size, max 100")  @QueryParam("size") @DefaultValue("20") int size) { ... }
}
```

```java
// Request DTO with schema annotations
public record CreateOrderRequest(
    @Schema(description = "Customer identifier", example = "cust-123")
    @NotBlank String customerId,

    @Schema(description = "Items to order", minItems = 1)
    @NotEmpty @Valid List<ItemRequest> items
) {}
```

---

## 24. Idempotency

Prevent duplicate processing of POST requests using a client-provided idempotency key.

```java
// domain/port/outbound/IdempotencyRepository.java
public interface IdempotencyRepository {
    boolean existsKey(String key);
    void saveKey(String key, String result);
    Optional<String> findResult(String key);
}
```

```java
// application/service/CreateOrderService.java
@Override
public Order execute(OrderRequest request) {
    if (request.idempotencyKey() != null) {
        Optional<String> cached = idempotencyRepo.findResult(request.idempotencyKey());
        if (cached.isPresent()) {
            return objectMapper.readValue(cached.get(), Order.class); // return cached result
        }
    }
    Order order = Order.create(request.customerId(), request.items());
    Order saved  = orderRepository.save(order);
    if (request.idempotencyKey() != null) {
        idempotencyRepo.saveKey(request.idempotencyKey(), objectMapper.writeValueAsString(saved));
    }
    return saved;
}
```

```java
// REST resource — read key from header
@POST
public Response create(
        @HeaderParam("Idempotency-Key") String idempotencyKey,
        @Valid CreateOrderRequest request) {
    OrderRequest domain = new OrderRequest(request.customerId(), request.items(), idempotencyKey);
    return Response.status(201).entity(createOrderUseCase.execute(domain)).build();
}
```

---

## 25. Outbox Pattern (Reliable Event Publishing)

Publishes events atomically with the business transaction — no dual-write problem.

```sql
-- V4__create_outbox_table.sql
CREATE TABLE outbox_events (
    id          UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    aggregate   VARCHAR(100) NOT NULL,
    event_type  VARCHAR(100) NOT NULL,
    payload     JSONB        NOT NULL,
    created_at  TIMESTAMP    NOT NULL DEFAULT NOW(),
    published   BOOLEAN      NOT NULL DEFAULT FALSE
);
```

```java
// domain/port/outbound/OutboxRepository.java
public interface OutboxRepository {
    void save(String aggregate, String eventType, String payload);
}
```

```java
// application/service/CreateOrderService.java
@Transactional          // order save + outbox save in ONE transaction
public Order execute(OrderRequest request) {
    Order order = Order.create(request.customerId(), request.items());
    Order saved = orderRepository.save(order);
    outboxRepository.save("Order", "OrderCreated",
            """
            {"orderId":%d,"customerId":"%s"}
            """.formatted(saved.getId(), saved.getCustomerId()));
    return saved;
}
```

```java
// infrastructure/adapter/messaging/OutboxPublisher.java — scheduled poller
@ApplicationScoped
public class OutboxPublisher {

    @Inject OutboxPanacheAdapter outboxAdapter;
    @Channel("orders-out") MutinyEmitter<String> emitter;

    @Scheduled(every = "5s")
    @Transactional
    void publishPendingEvents() {
        outboxAdapter.findUnpublished().forEach(event -> {
            emitter.sendAndAwait(event.getPayload());
            event.setPublished(true);
        });
    }
}
```

---

## Adding a New Module (checklist)

1. **Domain**: add input DTOs in `domain/dto/`, result models in `domain/model/`
2. **Domain**: define inbound port interface in `domain/port/inbound/`
3. **Domain**: define outbound port interface(s) in `domain/port/outbound/`
4. **Domain**: add new exceptions in `domain/exception/` + entry in `DomainErrorCode`
5. **Application**: create `@ApplicationScoped` service implementing the inbound port in `application/service/`
6. **Infrastructure**: create persistence adapter implementing outbound port in `infrastructure/adapter/persistence/`
7. **Infrastructure**: create `@Entity` + mapper in the same persistence package
8. **Infrastructure**: create JAX-RS resource in `infrastructure/adapter/rest/`
9. **Domain**: add new `DomainErrorCode` entry with `httpStatus` — the mapper updates itself automatically

---

## Known Quarkus Gotchas

**Panache active record vs repository style** — prefer repository style (`PanacheRepository<E>`) to keep JPA details out of domain entities.

**`@Transactional` placement** — annotate the persistence adapter method (outbound), never the use case service.

**Native image** — avoid reflection on domain classes; use `@RegisterForReflection` on infrastructure DTOs/entities if needed.

**Dev Services** — Quarkus auto-starts Postgres/Kafka containers in dev mode; no local setup required for development.

**Validation** — use `@Valid` + Bean Validation annotations only on REST DTOs (infrastructure layer). Domain objects validate their own invariants via constructor logic or factory methods.
