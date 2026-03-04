---
name: quarkus-hexagonal-reactive
description: Scaffold, validate or extend a Quarkus project following Hexagonal Architecture (Ports & Adapters) with Clean Code and Reactive (Mutiny) patterns. Use when the user wants to create reactive use cases, add domain logic, validate reactive patterns, or work with Mutiny Uni/Multi in a Quarkus hexagonal project.
argument-hint: "[action: scaffold|add-usecase|reactive-check|add-domain-logic] [name?]"
metadata:
  short-description: Quarkus Hexagonal + Clean Use Cases + Reactive Mutiny Stack
---

You are working on a Quarkus project that follows **Hexagonal Architecture (Ports & Adapters)** with **Clean Use Cases** and **Reactive (Mutiny)** patterns. Apply all rules below without deviation. Read existing code before making changes.

---

## Design Principles & Patterns (non-negotiable)

Every decision in this skill is grounded in the following principles. Understand them — do not break them silently.

### SOLID

| Principle | How it applies here |
|-----------|-------------------|
| **S** — Single Responsibility | One class per use case (`CreateOrderService`, `GetOrderService`). Controllers only map HTTP ↔ domain. |
| **O** — Open/Closed | `DomainErrorCode` carries `httpStatus` — adding a new exception never modifies `DomainExceptionMapper`. |
| **L** — Liskov Substitution | Any `OrderRepository` implementation must honor the port contract — same `Uni<T>` semantics, different storage. |
| **I** — Interface Segregation | Ports are small, focused interfaces. `OrderRepository` is separate from `OrderEventPublisher`. |
| **D** — Dependency Inversion | Use cases depend on port interfaces, never on adapters. CDI injects the reactive implementation at runtime. |

### GoF Patterns in use

| Pattern | Where |
|---------|-------|
| **Repository** | `OrderRepository` port + `OrderPanacheAdapter` — isolates persistence from domain |
| **Adapter** | Infrastructure adapters implement domain ports — the classic Adapter pattern |
| **Factory Method** | `Order.create(...)` — static factory validates invariants synchronously before construction |
| **Strategy** | Swappable adapters per port — e.g. mock vs real `OrderRepository` in tests |
| **Observer / Domain Events** | `OrderCreatedEvent` published reactively via `OrderEventPublisher` port |
| **Template Method** | `DomainException` defines the structure; subclasses fill in message + code |
| **Null Object** | `Uni<Optional<T>>` from outbound ports — never return `null` or `Uni.createFrom().item(null)` |

### Clean Code rules

- **Naming**: classes are nouns (`Order`, `CreateOrderService`), methods are verbs (`execute`, `save`, `findById`)
- **Use case method**: always named `execute(Request): Uni<Result>` — no ambiguity
- **Function size**: use case `execute()` orchestrates — chain of `flatMap/map/call` max 3-4 operators; business logic lives in the entity
- **No magic numbers**: all constants in `DomainErrorCode` or `@ConfigMapping` interfaces
- **No blocking in pipeline**: never use `.await()`, `Thread.sleep()`, or synchronized I/O inside a reactive chain

### Reactive Pipeline (Mutiny)

Every HTTP request flows through these layers as a non-blocking pipeline:

```
HTTP Request
    │
    ▼
REST Resource (RESTEasy Reactive)   ← validates input (@Valid), maps to domain DTO
    │  returns Uni<Response>
    ▼
Use Case (Service)                  ← orchestrates: validate, compose Uni chains
    │
    ├──flatMap──▶ Outbound Port ──▶ Panache Reactive Adapter   ← non-blocking DB
    │
    └──call────▶ Outbound Port ──▶ Kafka Reactive Adapter      ← non-blocking messaging
    │
    ▼  Uni<Order>
REST Resource                       ← maps domain result to response DTO
    │
    ▼
HTTP Response (Vert.x event loop)
    │
    ▼ (on failure)
DomainExceptionMapper               ← maps DomainException → JSON error response
UnexpectedExceptionMapper           ← catches everything else
```

**Pipeline composition rules:**
- `flatMap` — when the next step is also async (returns `Uni`)
- `map` — when the next step is synchronous (pure transformation)
- `call` — for side effects that don't change the item (logging, publishing events)
- `invoke` — for synchronous side effects (logging only — never I/O)
- `onFailure().recoverWithItem()` — only in infrastructure (fallback); never in domain
- The pipeline must be **fully non-blocking**: every operator runs on the Vert.x event loop

---

## 0. Project Scaffolding

### Create the project

```bash
quarkus create app com.comiagro:my-service \
  --extension=resteasy-reactive-jackson,\
hibernate-reactive-panache,\
reactive-pg-client,\
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
  -Dextensions="resteasy-reactive-jackson,hibernate-reactive-panache,\
reactive-pg-client,smallrye-openapi,hibernate-validator" \
  -DnoCode
```

### Required extensions

| Extension | Purpose |
|-----------|---------|
| `resteasy-reactive-jackson` | RESTEasy Reactive + JSON serialization |
| `hibernate-reactive-panache` | Panache Reactive repository pattern |
| `smallrye-openapi` | OpenAPI / Swagger UI |
| `hibernate-validator` | Bean Validation (`@Valid`, `@NotNull`, etc.) |

**Reactive database driver — choose one:**

| Database | Extension | Reactive URL format |
|----------|-----------|-------------------|
| PostgreSQL | `reactive-pg-client` | `postgresql://{host}:5432/{db}` |
| MySQL | `reactive-mysql-client` | `mysql://{host}:3306/{db}` |
| MariaDB | `reactive-mysql-client` | `mariadb://{host}:3306/{db}` |
| Microsoft SQL Server | `reactive-mssql-client` | `sqlserver://{host}:1433` |
| Oracle | `reactive-oracle-client` | `oracle:thin:@{host}:1521:{db}` |
| MongoDB | `mongodb-panache-reactive` | `mongodb://{host}:27017` |

> **Critical**: reactive drivers use `quarkus.datasource.reactive.url` — NOT `jdbc.url`. Never mix `jdbc-*` drivers with `hibernate-reactive`.
>
> H2 does **not** have a reactive driver — use PostgreSQL Dev Services for dev/test instead.

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
# ── Datasource (reactive — no jdbc.url) ─────────────────────────────────
# Choose the db-kind that matches your reactive driver extension:
#   postgresql | mysql | mariadb | mssql | oracle | mongodb
quarkus.datasource.db-kind=postgresql

quarkus.datasource.username=${DB_USER:app}
quarkus.datasource.password=${DB_PASS:secret}
quarkus.datasource.reactive.url=${DB_URL:postgresql://localhost:5432/appdb}

# ── Hibernate Reactive ───────────────────────────────────────────────────
quarkus.hibernate-orm.database.generation=${DB_GENERATION:validate}
quarkus.hibernate-orm.log.sql=false

# ── Vert.x ──────────────────────────────────────────────────────────────
quarkus.vertx.worker-pool-size=20

# ── OpenAPI ──────────────────────────────────────────────────────────────
quarkus.swagger-ui.always-include=true
quarkus.smallrye-openapi.info-title=${quarkus.application.name}
quarkus.smallrye-openapi.info-version=1.0.0
```

**Profile overrides by database:**

```properties
# PostgreSQL (default)
%dev.quarkus.datasource.reactive.url=postgresql://localhost:5432/appdb

# MySQL
# %dev.quarkus.datasource.db-kind=mysql
# %dev.quarkus.datasource.reactive.url=mysql://localhost:3306/appdb

# MariaDB
# %dev.quarkus.datasource.db-kind=mariadb
# %dev.quarkus.datasource.reactive.url=mariadb://localhost:3306/appdb

# SQL Server
# %dev.quarkus.datasource.db-kind=mssql
# %dev.quarkus.datasource.reactive.url=sqlserver://localhost:1433?databaseName=appdb

# MongoDB Reactive (uses mongodb-panache-reactive, not jdbc or reactive-*-client)
# %dev.quarkus.mongodb.connection-string=mongodb://localhost:27017
```

### Dev mode

```bash
quarkus dev   # starts with Dev Services (auto Postgres container, non-blocking)
```

---

## 1. Directory Structure (Screaming Architecture)

```
src/main/java/com/comiagro/app/
├── domain/                          # Inner hexagon — ZERO framework dependencies
│   ├── model/                       # Entities & Value Objects (Rich Domain Model)
│   ├── dto/                         # Input/Output — Java Records for immutability
│   ├── exception/                   # Business exceptions (COMI-XXXX codes)
│   └── port/
│       ├── inbound/                 # Use Case interfaces  (CreateOrderUseCase)
│       └── outbound/                # Infrastructure SPI   (OrderRepository)
├── application/                     # Use case implementations — orchestration only
│   └── service/                     # One class per use case (Single Responsibility)
└── infrastructure/                  # Outer hexagon — Quarkus, Mutiny, JPA, REST
    ├── adapter/
    │   ├── rest/                    # RESTEasy Reactive + DTO mappers
    │   └── persistence/             # Panache Reactive repositories + JPA entities
    ├── exception/                   # DomainExceptionMapper (global error handling)
    └── config/                      # CDI qualifiers & reactive producers
```

---

## 2. Dependency Rule (never violate)

```
infrastructure  →  application  →  domain
                        ↑
             implements ports at runtime
```

- **Domain**: no imports from `application` or `infrastructure`
- **Application**: only imports from `domain` — no Quarkus, no JPA
- **Infrastructure**: implements ports, knows the full stack

---

## 3. Reactive Use Case Pattern (SRP + Mutiny)

One class per business action. Use `Uni<T>` for all I/O operations.

```java
// src/main/java/com/comiagro/app/application/service/CreateOrderService.java
package com.comiagro.app.application.service;

import com.comiagro.app.domain.dto.OrderRequest;
import com.comiagro.app.domain.exception.InsufficientStockException;
import com.comiagro.app.domain.model.Order;
import com.comiagro.app.domain.port.inbound.CreateOrderUseCase;
import com.comiagro.app.domain.port.outbound.InventoryPort;
import com.comiagro.app.domain.port.outbound.OrderRepository;
import io.quarkus.hibernate.reactive.panache.common.WithTransaction;
import io.smallrye.mutiny.Uni;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;

@ApplicationScoped
public class CreateOrderService implements CreateOrderUseCase {

    @Inject OrderRepository repository;    // outbound port
    @Inject InventoryPort   inventoryPort; // outbound port

    @Override
    @WithTransaction  // transaction managed here — never in the domain
    public Uni<Order> execute(OrderRequest request) {
        // 1. Fail Fast — reactive validation
        return inventoryPort.hasStock(request.productId())
            .onItem().transformToUni(hasStock -> {
                if (!hasStock) {
                    throw new InsufficientStockException(request.productId());
                }
                // 2. Rich domain logic (synchronous inside the reactive chain)
                Order order = Order.create(request.customerId(), request.items());
                // 3. Reactive persistence
                return repository.save(order);
            });
    }
}
```

> **Rule**: if the operation touches I/O (DB, external API), it must return `Uni<T>` or `Multi<T>`. Never block inside a reactive chain.

---

## 4. Rich Domain Model (DDD — no anemic models)

The domain validates its own invariants. Use static factory methods.

```java
// src/main/java/com/comiagro/app/domain/model/Order.java
package com.comiagro.app.domain.model;

import com.comiagro.app.domain.exception.DomainErrorCode;
import com.comiagro.app.domain.exception.DomainException;
import java.util.List;

public class Order {

    private Long id;
    private final String customerId;
    private OrderStatus status;
    private final List<Item> items;

    private Order(String customerId, List<Item> items) {
        this.customerId = customerId;
        this.status     = OrderStatus.PENDING;
        this.items      = List.copyOf(items);
    }

    // Static factory — domain validates here, not in the service
    public static Order create(String customerId, List<Item> items) {
        if (items == null || items.isEmpty()) {
            throw new DomainException("Order items cannot be empty", DomainErrorCode.INVALID_INPUT);
        }
        return new Order(customerId, items);
    }

    // Behavior methods (rich model)
    public void confirm() {
        if (this.status != OrderStatus.PENDING) {
            throw new DomainException("Only PENDING orders can be confirmed", DomainErrorCode.UNPROCESSABLE);
        }
        this.status = OrderStatus.CONFIRMED;
    }
}
```

```java
// src/main/java/com/comiagro/app/domain/dto/OrderRequest.java
package com.comiagro.app.domain.dto;

import java.util.List;

// Records = immutable DTOs by default
public record OrderRequest(String customerId, List<ItemDTO> items) {}
```

---

## 5. Domain Exception Pattern

El **HTTP status vive en `DomainErrorCode`** — el mapper nunca necesita cambiar cuando se agrega una nueva excepción (Open/Closed Principle).

```java
// domain/exception/DomainErrorCode.java
public enum DomainErrorCode {
    INVALID_INPUT ("COMI-4001", 400),
    NOT_FOUND     ("COMI-4041", 404),
    CONFLICT      ("COMI-4091", 409),
    UNPROCESSABLE ("COMI-4221", 422),
    UNEXPECTED    ("COMI-5001", 500);

    public final String code;
    public final int    httpStatus;

    DomainErrorCode(String code, int httpStatus) {
        this.code       = code;
        this.httpStatus = httpStatus;
    }
}
```

```java
// domain/exception/DomainException.java
public abstract class DomainException extends RuntimeException {
    public final DomainErrorCode errorCode;
    protected DomainException(String message, DomainErrorCode errorCode) {
        super(message);
        this.errorCode = errorCode;
    }
}
```

```java
// domain/exception/InsufficientStockException.java
public class InsufficientStockException extends DomainException {
    public InsufficientStockException(String productId) {
        super("Insufficient stock for product: " + productId, DomainErrorCode.CONFLICT);
    }
}
```

**Checklist when adding a new exception:**
1. Add a new entry to `DomainErrorCode` with its `httpStatus`
2. Create `domain/exception/<Name>Exception.java`
3. ~~Add the `instanceof` mapping~~ — nothing else to change

---

## 6. Global Exception Handling

Two mappers registered via `@Provider` — Quarkus discovers them automatically.

```
@Provider DomainExceptionMapper      ← catches all DomainException subtypes
@Provider UnexpectedExceptionMapper  ← catches everything else (last resort)
```

`DomainExceptionMapper` is **closed for modification**: reads HTTP status from `errorCode.httpStatus`. Adding a new exception never requires touching this class.

```java
// infrastructure/exception/DomainExceptionMapper.java
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
// infrastructure/exception/UnexpectedExceptionMapper.java
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
// infrastructure/exception/ErrorResponse.java
public record ErrorResponse(int statusCode, String errorCode, String error, String message) {}
```

> **Por qué dos mappers?** JAX-RS resuelve el más específico primero. `DomainExceptionMapper` maneja todos los errores de negocio conocidos. `UnexpectedExceptionMapper` es la red de seguridad para todo lo demás — oculta intencionalmente el mensaje real al cliente.

---

## 7. Reactive Persistence Adapter (Panache)

```java
// infrastructure/adapter/persistence/OrderPanacheAdapter.java
@ApplicationScoped
public class OrderPanacheAdapter implements OrderRepository,
        PanacheRepositoryReactive<OrderEntity> {

    @Override
    public Uni<Order> save(Order order) {
        OrderEntity entity = OrderMapper.toEntity(order);
        return persist(entity)
                .map(OrderMapper::toDomain);
    }

    @Override
    public Uni<Optional<Order>> findById(Long id) {
        return find("id", id)
                .firstResultOptional()
                .map(opt -> opt.map(OrderMapper::toDomain));
    }
}
```

> Keep `OrderEntity` (`@Entity`) and `OrderMapper` in the `persistence/` package — they are infrastructure details the domain must never see.

---

## 8. Checklist: Clean & Reactive Validation

When reviewing or generating code, verify each point:

- [ ] **Uni/Multi?** Every I/O operation (DB, external API) returns `Uni<T>` or `Multi<T>`
- [ ] **@WithTransaction** used in the application layer (service), never in domain or REST resource
- [ ] **No blocking** inside a reactive chain — no `.await().indefinitely()` in production code
- [ ] **Rich model** — business rules and state transitions live in domain entities, not in services
- [ ] **Records for DTOs** — `OrderRequest`, `OrderResponse` are Java records (immutable)
- [ ] **Ports are interfaces** — all ports in `domain/port/` are pure Java interfaces
- [ ] **Layer mapping** — REST resource returns `OrderResponse`, never `OrderEntity` or `Order` directly
- [ ] **Exception codes** — every new exception has a `DomainErrorCode` entry with its `httpStatus`
- [ ] **Single Responsibility** — one service class per use case, no God services

---

## 9. Testing Strategy

Three layers — each with its own scope and tools.

```
src/test/java/com/comiagro/app/
├── domain/                          # Pure unit tests — synchronous, no Mutiny needed
│   ├── model/                       # Entity invariants, factory methods, state transitions
│   └── exception/                   # Exception messages and error codes
├── application/                     # Reactive use case unit tests — UniAssertSubscriber
│   └── service/
└── infrastructure/                  # Integration tests — @QuarkusTest + Dev Services
    ├── rest/                        # Reactive REST via RestAssured
    └── persistence/                 # Panache Reactive queries against real DB
```

### 9.1 Domain Unit Tests (synchronous — no Mutiny)

Domain logic is always synchronous. Test it with plain JUnit 5.

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
    void confirm_fails_when_not_pending() {
        Order order = Order.create("customer-1", List.of(new Item("p1", 1)));
        order.confirm();
        assertThatThrownBy(order::confirm)
                .isInstanceOf(DomainException.class);
    }
}
```

### 9.2 Reactive Use Case Tests (Mockito + UniAssertSubscriber)

Use `UniAssertSubscriber` to assert on reactive pipelines without blocking.

```java
// src/test/java/com/comiagro/app/application/service/CreateOrderServiceTest.java
package com.comiagro.app.application.service;

import com.comiagro.app.domain.exception.InsufficientStockException;
import com.comiagro.app.domain.port.outbound.InventoryPort;
import com.comiagro.app.domain.port.outbound.OrderRepository;
import io.smallrye.mutiny.Uni;
import io.smallrye.mutiny.helpers.test.UniAssertSubscriber;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.MockitoAnnotations;
import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

class CreateOrderServiceTest {

    @Mock  OrderRepository repository;
    @Mock  InventoryPort   inventoryPort;
    @InjectMocks CreateOrderService service;

    @BeforeEach
    void setUp() { MockitoAnnotations.openMocks(this); }

    @Test
    void execute_saves_and_returns_order_when_stock_available() {
        var request = new OrderRequest("customer-1", List.of(new ItemDTO("p1", 1)));
        var saved   = Order.create("customer-1", List.of(new Item("p1", 1)));

        when(inventoryPort.hasStock("p1")).thenReturn(Uni.createFrom().item(true));
        when(repository.save(any())).thenReturn(Uni.createFrom().item(saved));

        UniAssertSubscriber<Order> subscriber = service.execute(request)
                .subscribe().withSubscriber(UniAssertSubscriber.create());

        subscriber.assertCompleted();
        assertThat(subscriber.getItem().getCustomerId()).isEqualTo("customer-1");
        verify(repository, times(1)).save(any());
    }

    @Test
    void execute_fails_when_no_stock() {
        var request = new OrderRequest("customer-1", List.of(new ItemDTO("p1", 1)));
        when(inventoryPort.hasStock("p1")).thenReturn(Uni.createFrom().item(false));

        UniAssertSubscriber<Order> subscriber = service.execute(request)
                .subscribe().withSubscriber(UniAssertSubscriber.create());

        subscriber.assertFailedWith(InsufficientStockException.class, "p1");
        verify(repository, never()).save(any());
    }

    @Test
    void execute_propagates_repository_failure() {
        when(inventoryPort.hasStock(any())).thenReturn(Uni.createFrom().item(true));
        when(repository.save(any())).thenReturn(
                Uni.createFrom().failure(new RuntimeException("DB down")));

        UniAssertSubscriber<Order> subscriber = service.execute(
                new OrderRequest("c1", List.of(new ItemDTO("p1", 1))))
                .subscribe().withSubscriber(UniAssertSubscriber.create());

        subscriber.assertFailedWith(RuntimeException.class, "DB down");
    }
}
```

### 9.3 REST Integration Tests (@QuarkusTest + RestAssured)

```java
// src/test/java/com/comiagro/app/infrastructure/rest/OrderResourceTest.java
package com.comiagro.app.infrastructure.rest;

import com.comiagro.app.domain.model.Order;
import com.comiagro.app.domain.port.inbound.CreateOrderUseCase;
import io.quarkus.test.InjectMock;
import io.quarkus.test.junit.QuarkusTest;
import io.restassured.http.ContentType;
import io.smallrye.mutiny.Uni;
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
                .thenReturn(Uni.createFrom().item(
                        new Order(1L, "customer-1", OrderStatus.PENDING)));

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
    void post_order_returns_409_on_insufficient_stock() {
        when(createOrderUseCase.execute(any()))
                .thenReturn(Uni.createFrom().failure(
                        new InsufficientStockException("p1")));

        given()
            .contentType(ContentType.JSON)
            .body("""
                { "customerId": "c1", "items": [{ "productId": "p1", "quantity": 99 }] }
                """)
        .when()
            .post("/orders")
        .then()
            .statusCode(409)
            .body("errorCode", equalTo("COMI-4091"));
    }
}
```

### 9.4 Reactive Persistence Tests (@QuarkusTest + Dev Services)

```java
// src/test/java/com/comiagro/app/infrastructure/persistence/OrderPanacheAdapterTest.java
@QuarkusTest
class OrderPanacheAdapterTest {

    @Inject OrderPanacheAdapter adapter;

    @Test
    void save_and_findById_roundtrip() {
        Order order = Order.create("customer-1", List.of(new Item("p1", 1)));

        UniAssertSubscriber<Order> saveSub = adapter.save(order)
                .subscribe().withSubscriber(UniAssertSubscriber.create());
        saveSub.assertCompleted();
        Long id = saveSub.getItem().getId();
        assertThat(id).isNotNull();

        UniAssertSubscriber<Optional<Order>> findSub = adapter.findById(id)
                .subscribe().withSubscriber(UniAssertSubscriber.create());
        findSub.assertCompleted();
        assertThat(findSub.getItem())
                .isPresent()
                .get()
                .extracting(Order::getCustomerId)
                .isEqualTo("customer-1");
    }
}
```

> **Dev Services**: Quarkus auto-starts a Postgres container for tests. For reactive tests with `@WithTransaction`, use `@RunOnVertxContext` to avoid running Mutiny chains off the Vert.x event loop.

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

Run coverage:
```bash
./mvnw verify          # fails build if coverage < 80%
./mvnw jacoco:report   # generates target/site/jacoco/index.html
```

**Coverage targets by layer:**

| Layer | Target | Why |
|-------|--------|-----|
| `domain/model` | ≥ 90% | Pure synchronous logic — easiest to test |
| `domain/exception` | ≥ 90% | Simple constructors |
| `application/service` | ≥ 85% | Core reactive flow — use `UniAssertSubscriber` |
| `infrastructure/adapter/rest` | ≥ 80% | Via `@QuarkusTest` + RestAssured |
| `infrastructure/exception` | ≥ 80% | Via REST integration tests |
| `infrastructure/config` | excluded | CDI wiring, not testable in isolation |

> **Note on reactive coverage**: JaCoCo instruments bytecode — Mutiny lambdas are covered when `UniAssertSubscriber` exercises them. Use `assertCompleted()` AND `assertFailedWith()` tests to cover both success and failure branches.

### 9.6 Testing Rules

- **Domain tests** → plain JUnit 5 + AssertJ. Zero annotations, zero mocks, zero Mutiny.
- **Use case tests** → Mockito (`@Mock` + `@InjectMocks`) + `UniAssertSubscriber`. No `@QuarkusTest`.
- **REST tests** → `@QuarkusTest` + `@InjectMock` on the **inbound port**. Mock returns `Uni.createFrom().item(...)` or `Uni.createFrom().failure(...)`.
- **Persistence tests** → `@QuarkusTest` + `@RunOnVertxContext` if needed. Let Dev Services provide the DB.
- **Never** use `.await().indefinitely()` in tests — use `UniAssertSubscriber` instead.
- **Never** mock `OrderEntity` — it is an infrastructure detail invisible to use case tests.
- **Never** test `ExceptionMapper` in isolation — test it through the REST layer.

---

## 10. Value Objects (DDD)

Value Objects encapsulan validación y semántica — evitan primitivos desnudos (`String email`, `Long id`).

```java
// domain/model/vo/Email.java
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

> **Rule**: if a primitive has validation rules or behavior, make it a Value Object. Use records for immutability. Value Object validation is synchronous — never reactive.

---

## 11. Mapper Pattern

Mappers translate between layers. Keep them as static utility classes inside the infrastructure package that owns the translation.

```java
// infrastructure/adapter/persistence/OrderMapper.java
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
final class OrderResponseMapper {
    private OrderResponseMapper() {}

    static OrderResponse toResponse(Order domain) {
        return new OrderResponse(domain.getId(), domain.getCustomerId(),
                domain.getStatus().name(), domain.getCreatedAt());
    }
}
```

**Rules:**
- Mappers live in the **infrastructure** package — never in domain
- REST mappers: `domain → response DTO`; Persistence mappers: `domain ↔ entity`
- Mappers are **always synchronous** — wrap in reactive chain when needed: `Uni.createFrom().item(() -> OrderMapper.toDomain(entity))`

---

## 12. Logging Conventions

```java
private static final Logger LOG = Logger.getLogger(CreateOrderService.class);

// INFO  — significant business events
LOG.infof("Order created: id=%d customer=%s", order.getId(), order.getCustomerId());

// WARN  — domain exceptions (expected, recoverable)
LOG.warnf("[%s] %s: %s", ex.errorCode.code, ex.getClass().getSimpleName(), ex.getMessage());

// ERROR — unexpected exceptions (bugs, infra failures)
LOG.errorf(ex, "[%s] Unhandled exception", DomainErrorCode.UNEXPECTED.code);
```

**Rules:**
- Log at **WARN** for `DomainException` — it is expected business flow
- Log at **ERROR** only in `UnexpectedExceptionMapper`
- Never log inside a Mutiny chain with blocking calls — use `.invoke()` for side effects:

```java
return repository.save(order)
    .invoke(saved -> LOG.infof("Order saved: id=%d", saved.getId()));
```

---

## 13. Health Checks

```xml
<dependency>
  <groupId>io.quarkus</groupId>
  <artifactId>quarkus-smallrye-health</artifactId>
</dependency>
```

```java
// infrastructure/health/DatabaseHealthCheck.java
@Readiness
@ApplicationScoped
public class DatabaseHealthCheck implements HealthCheck {

    @Inject
    io.vertx.mutiny.pgclient.PgPool pgPool;

    @Override
    public HealthCheckResponse call() {
        // block only in health check context — not in request path
        try {
            pgPool.query("SELECT 1").execute().await().atMost(Duration.ofSeconds(2));
            return HealthCheckResponse.up("database");
        } catch (Exception e) {
            return HealthCheckResponse.down("database");
        }
    }
}
```

| Endpoint | Annotation | Purpose |
|----------|-----------|---------|
| `/q/health/live` | `@Liveness` | Is the process alive? |
| `/q/health/ready` | `@Readiness` | Is it ready to receive traffic? |
| `/q/health` | both | Combined |

---

## 14. Pagination Pattern (Reactive)

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
        return new PageResult<>(content, (int) Math.ceil((double) total / req.size()), total, req.page());
    }
}
```

```java
// domain/port/outbound/OrderRepository.java
Uni<PageResult<Order>> findAll(PageRequest pageRequest);
```

```java
// infrastructure/adapter/persistence/OrderPanacheAdapter.java
@Override
public Uni<PageResult<Order>> findAll(PageRequest req) {
    return count()
        .flatMap(total -> findAll(Sort.by("createdAt").descending())
            .page(req.page(), req.size())
            .list()
            .map(entities -> {
                List<Order> content = entities.stream().map(OrderMapper::toDomain).toList();
                return PageResult.of(content, total, req);
            }));
}
```

---

## 15. Security (JWT + @RolesAllowed)

```xml
<dependency>
  <groupId>io.quarkus</groupId>
  <artifactId>quarkus-smallrye-jwt</artifactId>
</dependency>
```

```properties
mp.jwt.verify.publickey.location=META-INF/resources/publicKey.pem
mp.jwt.verify.issuer=https://auth.comiagro.com
```

```java
@Path("/orders")
@Authenticated
public class OrderResource {

    @Inject JsonWebToken jwt;

    @POST
    @RolesAllowed("orders:write")
    public Uni<Response> create(@Valid CreateOrderRequest request) {
        return createOrderUseCase.execute(request.toDomain())
                .map(order -> Response.status(201).entity(OrderResponseMapper.toResponse(order)).build());
    }

    @GET
    @RolesAllowed({"orders:read", "admin"})
    public Uni<PageResult<OrderResponse>> list(
            @QueryParam("page") @DefaultValue("0") int page,
            @QueryParam("size") @DefaultValue("20") int size) {
        return listOrdersUseCase.execute(new PageRequest(page, size))
                .map(result -> new PageResult<>(
                    result.content().stream().map(OrderResponseMapper::toResponse).toList(),
                    result.totalElements(), result.totalPages(), result.page()));
    }
}
```

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
@ApplicationScoped
public class CreateOrderService implements CreateOrderUseCase {

    @Inject MeterRegistry registry;

    @Override
    @WithTransaction
    public Uni<Order> execute(OrderRequest request) {
        long start = System.currentTimeMillis();
        return inventoryPort.hasStock(request.productId())
            .onItem().transformToUni(hasStock -> {
                if (!hasStock) throw new InsufficientStockException(request.productId());
                return repository.save(Order.create(request.customerId(), request.items()));
            })
            .invoke(order -> registry.counter("order.created").increment())
            .onFailure().invoke(ex -> registry.counter("order.failed",
                    "reason", ex.getClass().getSimpleName()).increment());
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

Quarkus auto-instruments RESTEasy Reactive, Hibernate Reactive, and Mutiny pipelines — no code changes needed for basic tracing.

---

## 17. Optional vs Exception — When to Use Each

| Scenario | Return |
|----------|--------|
| Query that may find nothing (expected) | `Uni<Optional<T>>` |
| Query that MUST find a result (business invariant) | throw `NotFoundException` inside the chain |
| Void operation that may not find the target | emit failure with `NotFoundException` |

```java
// domain/port/outbound/OrderRepository.java
Uni<Optional<Order>> findById(Long id);       // caller decides if absent is ok
Uni<List<Order>> findByCustomer(String id);   // empty list, never null or empty Uni

// application/service/GetOrderService.java
public Uni<Order> execute(Long id) {
    return orderRepository.findById(id)
            .map(opt -> opt.orElseThrow(() -> new OrderNotFoundException(id)));
}
```

**Rules:**
- Outbound ports return `Uni<Optional<T>>` — they don't know if absence is an error
- Use cases apply the business invariant inside `.map()` — throw synchronously, Mutiny wraps it as failure
- Never return `null` or `Uni.createFrom().item(null)` from any port

---

## 18. DB Migrations (Flyway)

```xml
<dependency>
  <groupId>io.quarkus</groupId>
  <artifactId>quarkus-flyway</artifactId>
</dependency>
```

```properties
quarkus.flyway.migrate-at-start=true
quarkus.flyway.locations=classpath:db/migration
quarkus.flyway.baseline-on-migrate=true
%test.quarkus.flyway.clean-at-start=true
```

```
src/main/resources/db/migration/
├── V1__create_orders_table.sql
└── V2__add_order_status_index.sql
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
- Never modify an existing migration — always add a new version
- `quarkus.hibernate-orm.database.generation=none` — Flyway owns the schema
- Flyway runs synchronously at startup before Vert.x accepts traffic

---

## 19. Config Management (@ConfigMapping)

```java
// infrastructure/config/AppConfig.java
@ConfigMapping(prefix = "app")
public interface AppConfig {
    OrderConfig order();
    SecurityConfig security();

    interface OrderConfig {
        @WithDefault("100") int maxItemsPerOrder();
        @WithDefault("USD") String defaultCurrency();
    }

    interface SecurityConfig {
        String jwtIssuer();
        @WithDefault("3600") long tokenExpirationSeconds();
    }
}
```

```properties
app.order.max-items-per-order=50
app.security.jwt-issuer=https://auth.comiagro.com

%dev.app.order.max-items-per-order=9999
%test.app.security.jwt-issuer=https://test.comiagro.com
%prod.app.security.jwt-issuer=${JWT_ISSUER}
```

---

## 20. Messaging / Kafka (SmallRye Reactive Messaging)

```xml
<dependency>
  <groupId>io.quarkus</groupId>
  <artifactId>quarkus-smallrye-reactive-messaging-kafka</artifactId>
</dependency>
```

```java
// domain/model/event/OrderCreatedEvent.java
public record OrderCreatedEvent(Long orderId, String customerId, Instant occurredAt) {}
```

```java
// domain/port/outbound/OrderEventPublisher.java
public interface OrderEventPublisher {
    Uni<Void> publish(OrderCreatedEvent event);
}
```

```java
// infrastructure/adapter/messaging/KafkaOrderEventAdapter.java
@ApplicationScoped
public class KafkaOrderEventAdapter implements OrderEventPublisher {

    @Channel("orders-out")
    MutinyEmitter<String> emitter;

    @Inject ObjectMapper objectMapper;

    @Override
    public Uni<Void> publish(OrderCreatedEvent event) {
        return Uni.createFrom().item(() -> {
            try { return objectMapper.writeValueAsString(event); }
            catch (JsonProcessingException e) { throw new RuntimeException(e); }
        }).flatMap(emitter::send);
    }
}
```

```java
// infrastructure/adapter/messaging/OrderEventConsumer.java
@ApplicationScoped
public class OrderEventConsumer {

    @Incoming("orders-in")
    public Uni<Void> consume(String payload) {
        // deserialize + call use case reactively
        return Uni.createFrom().item(payload)
                .map(p -> objectMapper.readValue(p, OrderCreatedEvent.class))
                .flatMap(event -> processEventUseCase.execute(event))
                .replaceWithVoid();
    }
}
```

```properties
mp.messaging.outgoing.orders-out.connector=smallrye-kafka
mp.messaging.outgoing.orders-out.topic=orders
mp.messaging.outgoing.orders-out.value.serializer=org.apache.kafka.common.serialization.StringSerializer
mp.messaging.incoming.orders-in.connector=smallrye-kafka
mp.messaging.incoming.orders-in.topic=orders
mp.messaging.incoming.orders-in.group.id=my-service
```

---

## 21. Resilience (SmallRye Fault Tolerance)

```xml
<dependency>
  <groupId>io.quarkus</groupId>
  <artifactId>quarkus-smallrye-fault-tolerance</artifactId>
</dependency>
```

Apply **only on infrastructure adapters** — never on domain or use cases.

```java
// infrastructure/adapter/outbound/ExternalInventoryAdapter.java
@ApplicationScoped
public class ExternalInventoryAdapter implements InventoryPort {

    @Retry(maxRetries = 3, delay = 500, delayUnit = ChronoUnit.MILLIS)
    @Timeout(value = 2, unit = ChronoUnit.SECONDS)
    @CircuitBreaker(requestVolumeThreshold = 10, failureRatio = 0.5, delay = 5, delayUnit = ChronoUnit.SECONDS)
    @Fallback(fallbackMethod = "fallbackHasStock")
    @Override
    public Uni<Boolean> hasStock(String productId) {
        return externalApi.checkStock(productId);
    }

    Uni<Boolean> fallbackHasStock(String productId) {
        LOG.warnf("Fallback triggered for product: %s", productId);
        return Uni.createFrom().item(false);
    }
}
```

> For reactive methods returning `Uni<T>`, SmallRye Fault Tolerance 6+ supports the annotations natively — no extra adapter needed.

---

## 22. Containerization

```bash
# JVM image
./mvnw package
docker build -f src/main/docker/Dockerfile.jvm -t comiagro/my-service:latest .

# Native image (smaller, faster startup)
./mvnw package -Pnative -Dquarkus.native.container-build=true
docker build -f src/main/docker/Dockerfile.native -t comiagro/my-service:native .
```

```properties
%prod.quarkus.http.host=0.0.0.0
%prod.quarkus.log.console.json=true
%prod.quarkus.datasource.reactive.url=postgresql://${DB_HOST}:5432/${DB_NAME}
```

**Native image gotchas:**
- Mutiny and RESTEasy Reactive are native-compatible out of the box
- Register domain classes with `@RegisterForReflection` only if accessed via reflection (Jackson serialization of non-record types)
- Test native build in CI: `./mvnw verify -Pnative`

---

## 23. OpenAPI Annotations

```java
@Path("/orders")
@Tag(name = "Orders", description = "Order management operations")
public class OrderResource {

    @POST
    @Operation(summary = "Create a new order")
    @APIResponse(responseCode = "201", description = "Order created",
        content = @Content(schema = @Schema(implementation = OrderResponse.class)))
    @APIResponse(responseCode = "409", description = "Insufficient stock",
        content = @Content(schema = @Schema(implementation = ErrorResponse.class)))
    public Uni<Response> create(@Valid CreateOrderRequest request) { ... }
}
```

```java
public record CreateOrderRequest(
    @Schema(description = "Customer ID", example = "cust-123") @NotBlank String customerId,
    @Schema(description = "Items to order", minItems = 1) @NotEmpty @Valid List<ItemRequest> items
) {}
```

---

## 24. Idempotency

```java
// domain/port/outbound/IdempotencyRepository.java
public interface IdempotencyRepository {
    Uni<Optional<String>> findResult(String key);
    Uni<Void> saveKey(String key, String result);
}
```

```java
// application/service/CreateOrderService.java
@Override
@WithTransaction
public Uni<Order> execute(OrderRequest request) {
    if (request.idempotencyKey() == null) {
        return doCreate(request);
    }
    return idempotencyRepo.findResult(request.idempotencyKey())
        .flatMap(cached -> cached.isPresent()
            ? Uni.createFrom().item(deserialize(cached.get()))
            : doCreate(request)
                .call(saved -> idempotencyRepo.saveKey(
                        request.idempotencyKey(), serialize(saved))));
}
```

```java
// REST — read from header
@POST
public Uni<Response> create(
        @HeaderParam("Idempotency-Key") String idempotencyKey,
        @Valid CreateOrderRequest request) {
    return createOrderUseCase
            .execute(new OrderRequest(request.customerId(), request.items(), idempotencyKey))
            .map(order -> Response.status(201).entity(OrderResponseMapper.toResponse(order)).build());
}
```

---

## 25. Outbox Pattern (Reliable Event Publishing)

Publishes events atomically with the business transaction using `@WithTransaction`.

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
// application/service/CreateOrderService.java
@Override
@WithTransaction
public Uni<Order> execute(OrderRequest request) {
    Order order = Order.create(request.customerId(), request.items());
    return repository.save(order)
        .call(saved -> outboxRepository.save("Order", "OrderCreated",
                """
                {"orderId":%d,"customerId":"%s"}
                """.formatted(saved.getId(), saved.getCustomerId())));
}
```

```java
// infrastructure/adapter/messaging/OutboxPublisher.java
@ApplicationScoped
public class OutboxPublisher {

    @Inject OutboxPanacheAdapter outboxAdapter;
    @Channel("orders-out") MutinyEmitter<String> emitter;

    @Scheduled(every = "5s")
    Uni<Void> publishPendingEvents() {
        return outboxAdapter.findUnpublished()
            .onItem().transformToMulti(list -> Multi.createFrom().iterable(list))
            .onItem().transformToUniAndConcatenate(event ->
                emitter.send(event.getPayload())
                    .call(() -> outboxAdapter.markPublished(event.getId())))
            .toUni().replaceWithVoid();
    }
}
```

---

## Adding a New Use Case (checklist)

1. **Domain**: add `record InputRequest(...)` in `domain/dto/`
2. **Domain**: add interface `NombreUseCase` in `domain/port/inbound/` returning `Uni<T>`
3. **Domain**: add outbound port interface(s) in `domain/port/outbound/` if new I/O is needed
4. **Domain**: add exception(s) in `domain/exception/` + entry in `DomainErrorCode`
5. **Application**: create `NombreService implements NombreUseCase` in `application/service/` with `@WithTransaction`
6. **Infrastructure**: create/update reactive adapter in `infrastructure/adapter/persistence/`
7. **Infrastructure**: add `@Path` method in the REST resource in `infrastructure/adapter/rest/`
8. **Domain**: add new `DomainErrorCode` entry with `httpStatus` — the mapper updates itself automatically
