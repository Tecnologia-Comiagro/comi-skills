---
name: quarkus-vertical-slice
description: Scaffold or extend a Quarkus project using Vertical Slice Architecture. Use when organizing code by feature rather than by layer, when multiple teams work on independent features, or when each feature has its own complexity and lifecycle.
license: MIT
argument-hint: "[action: scaffold|add-slice|add-feature] [name?]"
metadata:
  short-description: Quarkus Vertical Slice — feature-first organization
  version: "1.1.0"
  author: jorge.reyes@comiagro.com
---

You are working on a Quarkus project using **Vertical Slice Architecture**. Apply all patterns below. Read existing code before making changes.

## When to Apply

- Multiple teams work on **independent features** and want to avoid merge conflicts
- Each feature has its own complexity and lifecycle — they should be deployable independently
- Adding a new feature slice (endpoint + handler + entity all in one folder)
- The codebase is a **pre-microservice monolith** being prepared for extraction
- Validating that feature slices do not import from each other
- The user wants to organize code by business feature, not by technical layer

---

## When to Use This Architecture

| Use Vertical Slice when... | Avoid when... |
|---------------------------|---------------|
| Multiple teams, one codebase | Single-feature service |
| Features have different complexity | Strong shared domain needed |
| Fast independent feature delivery | Many cross-cutting business rules |
| Microservice that will be split later | Heavy reuse between features |
| Feature flags / A-B testing per slice | |

**Compared to other architectures:**
- Opposite of **Layered** — organized by feature, not by technical layer
- Less opinionated than **Hexagonal** — each slice chooses its internal structure
- Simpler than **CQRS** — but can use CQRS within a slice if needed
- Easy to extract into a microservice — each slice is nearly self-contained

---

## Directory Structure

```
src/main/java/com/comiagro/app/
├── shared/                          # Cross-cutting concerns only
│   ├── exception/                   # GlobalExceptionMapper, AppException
│   ├── pagination/                  # PageRequest, PageResult
│   └── security/                    # JWT utils, @RolesAllowed helpers
└── feature/
    ├── orders/                      # Self-contained slice
    │   ├── CreateOrder.java         # Command + handler + endpoint in one file (or split)
    │   ├── GetOrder.java
    │   ├── ListOrders.java
    │   ├── OrderEntity.java         # JPA entity — local to this slice
    │   ├── OrderRepository.java     # Panache repo — local to this slice
    │   └── OrderException.java      # Exceptions — local to this slice
    ├── inventory/                   # Independent slice
    │   ├── CheckStock.java
    │   └── ...
    └── customers/                   # Independent slice
        └── ...
```

**Rules:**
- Slices do NOT import from each other's packages — communicate via events or HTTP
- `shared/` contains only infrastructure utilities — no business logic
- Each slice owns its persistence — no shared repository between slices

---

## 1. Slice Pattern (Feature as a Unit)

Each feature is a vertical cut through all technical layers. Minimal files, maximum cohesion.

```java
// feature/orders/CreateOrder.java
package com.comiagro.app.feature.orders;

import com.comiagro.app.shared.exception.AppException;
import com.comiagro.app.shared.exception.AppErrorCode;
import io.quarkus.hibernate.orm.panache.PanacheRepository;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.transaction.Transactional;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotEmpty;
import jakarta.ws.rs.*;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import java.util.List;

// ── Request DTO ─────────────────────────────────────────────────────────
record CreateOrderRequest(
    @NotBlank String customerId,
    @NotEmpty List<String> productIds
) {}

// ── Response DTO ────────────────────────────────────────────────────────
record CreateOrderResponse(Long id, String customerId, String status) {}

// ── Handler (business logic) ─────────────────────────────────────────────
@ApplicationScoped
class CreateOrderHandler {

    @Inject OrderRepository repository;

    @Transactional
    CreateOrderResponse handle(CreateOrderRequest request) {
        if (request.productIds().isEmpty())
            throw new AppException("Order must have products", AppErrorCode.INVALID_INPUT);

        OrderEntity order = new OrderEntity();
        order.customerId = request.customerId();
        order.status = "PENDING";
        repository.persist(order);
        return new CreateOrderResponse(order.id, order.customerId, order.status);
    }
}

// ── Endpoint ─────────────────────────────────────────────────────────────
@Path("/orders")
@Produces(MediaType.APPLICATION_JSON)
@Consumes(MediaType.APPLICATION_JSON)
public class CreateOrderEndpoint {

    @Inject CreateOrderHandler handler;

    @POST
    public Response create(@Valid CreateOrderRequest request) {
        return Response.status(201).entity(handler.handle(request)).build();
    }
}
```

---

## 2. Slice-Local Entity and Repository

```java
// feature/orders/OrderEntity.java
@Entity
@Table(name = "orders")
class OrderEntity extends PanacheEntityBase {
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    Long id;
    String customerId;
    String status;
    Instant createdAt = Instant.now();
}

// feature/orders/OrderRepository.java
@ApplicationScoped
class OrderRepository implements PanacheRepository<OrderEntity> {
    Optional<OrderEntity> findByIdSafe(Long id) {
        return findByIdOptional(id);
    }
}
```

---

## 3. Cross-Slice Communication (Events — no direct imports)

```java
// shared/event/OrderCreatedEvent.java
public record OrderCreatedEvent(Long orderId, String customerId) {}

// feature/orders/CreateOrder.java — publishes
@Channel("order-events") MutinyEmitter<OrderCreatedEvent> emitter;
emitter.sendAndAwait(new OrderCreatedEvent(order.id, order.customerId));

// feature/inventory/ReserveStock.java — consumes (different slice)
@Incoming("order-events")
public void on(OrderCreatedEvent event) {
    inventoryService.reserve(event.orderId(), event.customerId());
}
```

---

## 4. Shared Exceptions

```java
// shared/exception/AppErrorCode.java
public enum AppErrorCode {
    NOT_FOUND    ("APP-4041", 404),
    INVALID_INPUT("APP-4001", 400),
    CONFLICT     ("APP-4091", 409),
    UNEXPECTED   ("APP-5001", 500);

    public final String code;
    public final int    httpStatus;
    AppErrorCode(String code, int httpStatus) {
        this.code = code; this.httpStatus = httpStatus;
    }
}

// shared/exception/AppException.java
public class AppException extends RuntimeException {
    public final AppErrorCode errorCode;
    public AppException(String message, AppErrorCode errorCode) {
        super(message); this.errorCode = errorCode;
    }
}

// shared/exception/GlobalExceptionMapper.java
@Provider
public class GlobalExceptionMapper implements ExceptionMapper<AppException> {
    @Override
    public Response toResponse(AppException ex) {
        return Response.status(ex.errorCode.httpStatus)
                .entity(new ErrorResponse(ex.errorCode.httpStatus, ex.errorCode.code,
                        ex.getClass().getSimpleName(), ex.getMessage()))
                .build();
    }
}
```

---

## 5. Testing Strategy

Each slice is tested independently — no shared test setup.

```java
// Test the handler directly (unit test — no Quarkus)
class CreateOrderHandlerTest {
    @Mock OrderRepository repository;
    @InjectMocks CreateOrderHandler handler;

    @Test
    void handle_creates_order() {
        var request = new CreateOrderRequest("c1", List.of("p1"));
        var result  = handler.handle(request);
        assertThat(result.status()).isEqualTo("PENDING");
        verify(repository).persist(any(OrderEntity.class));
    }

    @Test
    void handle_fails_with_empty_products() {
        assertThatThrownBy(() -> handler.handle(new CreateOrderRequest("c1", List.of())))
                .isInstanceOf(AppException.class);
    }
}

// Integration test for the endpoint
@QuarkusTest
class CreateOrderEndpointTest {
    @InjectMock CreateOrderHandler handler;

    @Test
    void post_returns_201() {
        when(handler.handle(any())).thenReturn(new CreateOrderResponse(1L, "c1", "PENDING"));
        given().contentType(ContentType.JSON)
               .body("""{"customerId":"c1","productIds":["p1"]}""")
        .when().post("/orders")
        .then().statusCode(201).body("id", equalTo(1));
    }
}
```

**Coverage: ≥ 80%** per slice — each slice is tested in isolation.

---

## Known Gotchas

**Shared entity temptation** — when two slices need `OrderEntity`, the instinct is to move it to `shared/`. Resist — if two slices truly share a concept, consider merging them or using events.

**Package visibility** — mark slice-internal classes as package-private (`class`, not `public class`) so other slices can't import them accidentally.

**When to split into microservices** — each vertical slice maps cleanly to a microservice. When a slice grows too large, extract it: copy the slice folder, update the package, done.

---

## Pre-commit Checklist

- [ ] **[CRITICAL]** Global exception handler in `shared/exception/` — no raw exceptions exposed to clients from any slice
- [ ] **[CRITICAL]** Slices do not import classes from other slices' packages — cross-slice communication uses events only
- [ ] **[HIGH]** Slice-internal classes are package-private (`class`, not `public class`) where possible
- [ ] **[HIGH]** Coverage ≥ 80% per slice — handler unit tests + endpoint integration tests
- [ ] **[HIGH]** Flyway migrations used — no `database.generation=create` in production
- [ ] **[MEDIUM]** Cross-slice events use `shared/event/` records — no direct object sharing
- [ ] **[MEDIUM]** OpenAPI annotations present on all public endpoints within each slice
- [ ] **[LOW]** Each slice is self-contained enough to be extracted into a microservice without touching other slices
