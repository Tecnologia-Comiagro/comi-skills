---
name: quarkus-clean
description: Scaffold or extend a Quarkus project using Clean Architecture (Uncle Bob). Use when the domain has complex business rules, multiple use cases, and must remain independent of frameworks, databases, and delivery mechanisms.
license: MIT
argument-hint: "[action: scaffold|add-usecase|add-entity|add-gateway] [name?]"
metadata:
  short-description: Quarkus Clean Architecture — domain-centric with use case rings
  version: "1.1.0"
  author: jorge.reyes@comiagro.com
---

You are working on a Quarkus project using **Clean Architecture** (Robert C. Martin). Apply all patterns below. Read existing code before making changes.

## When to Apply

- Building a **long-lived enterprise service** with rich domain logic and many use cases
- The domain must remain **framework-independent** — switching from Quarkus must be possible
- Adding entities, use cases, or gateways to a Clean Architecture project
- Validating that domain classes have zero imports from `jakarta.*` or `quarkus.*`
- The project requires strict input/output boundaries for every use case
- Auditing whether business rules have leaked into adapters or frameworks

---

## When to Use This Architecture

| Use Clean Architecture when... | Avoid when... |
|-------------------------------|---------------|
| Complex domain with many rules | Simple CRUD service |
| Must survive framework changes | Short-lived prototype |
| Multiple delivery mechanisms (REST, CLI, Kafka) | Small team needing fast delivery |
| Long-lived enterprise system | No real business logic |
| Testability is critical | |

**Compared to other architectures:**
- More explicit rings than **Hexagonal** — Entities, Use Cases, Interface Adapters, Frameworks
- Stricter dependency rule than **Layered** — inner rings know nothing of outer rings
- Similar to **Hexagonal** but emphasizes use case as first-class citizen with input/output boundaries

---

## Directory Structure (Concentric Rings)

```
src/main/java/com/comiagro/app/
├── entity/                      # Ring 1 — Enterprise business rules (plain Java)
│   ├── Order.java               # Enterprise entity with business rules
│   ├── OrderStatus.java
│   └── vo/                      # Value Objects
├── usecase/                     # Ring 2 — Application business rules
│   ├── port/
│   │   ├── in/                  # Input boundaries (interfaces the controller calls)
│   │   └── out/                 # Output boundaries (interfaces the use case calls)
│   ├── CreateOrderUseCase.java  # Use case interactor
│   └── GetOrderUseCase.java
├── adapter/                     # Ring 3 — Interface Adapters
│   ├── controller/              # REST controllers + request/response DTOs
│   ├── presenter/               # Response mappers (optional, for complex output)
│   └── gateway/                 # DB gateway implementations
└── framework/                   # Ring 4 — Frameworks & Drivers
    ├── persistence/             # JPA entities, Panache repos
    ├── web/                     # Quarkus/JAX-RS config
    └── exception/               # ExceptionMappers
```

**Dependency Rule — strictly inward:**
```
framework → adapter → usecase → entity
```
Nothing in an inner ring knows about an outer ring.

---

## 1. Entity Ring (Enterprise Rules)

```java
// entity/Order.java — zero framework imports
public class Order {
    private final Long id;
    private final String customerId;
    private OrderStatus status;
    private final List<OrderLine> lines;

    private Order(Long id, String customerId, List<OrderLine> lines) {
        this.id = id; this.customerId = customerId;
        this.status = OrderStatus.PENDING;
        this.lines = List.copyOf(lines);
    }

    public static Order create(String customerId, List<OrderLine> lines) {
        if (lines == null || lines.isEmpty())
            throw new BusinessRuleViolation("Order must have at least one line");
        return new Order(null, customerId, lines);
    }

    public void approve() {
        if (status != OrderStatus.PENDING)
            throw new BusinessRuleViolation("Only PENDING orders can be approved");
        this.status = OrderStatus.APPROVED;
    }

    // getters only — no setters
}
```

```java
// entity/BusinessRuleViolation.java — no framework imports
public class BusinessRuleViolation extends RuntimeException {
    public BusinessRuleViolation(String message) { super(message); }
}
```

---

## 2. Use Case Ring (Input/Output Boundaries)

```java
// usecase/port/in/CreateOrderInputBoundary.java
public interface CreateOrderInputBoundary {
    CreateOrderOutputData execute(CreateOrderInputData input);
}

// usecase/CreateOrderInputData.java — plain data struct
public record CreateOrderInputData(String customerId, List<String> productIds) {}

// usecase/CreateOrderOutputData.java
public record CreateOrderOutputData(Long id, String customerId, String status) {}
```

```java
// usecase/port/out/OrderGateway.java
public interface OrderGateway {
    Order save(Order order);
    Optional<Order> findById(Long id);
}
```

```java
// usecase/CreateOrderUseCase.java
@ApplicationScoped
public class CreateOrderUseCase implements CreateOrderInputBoundary {

    @Inject OrderGateway orderGateway;

    @Override
    public CreateOrderOutputData execute(CreateOrderInputData input) {
        List<OrderLine> lines = input.productIds().stream()
                .map(id -> new OrderLine(id, 1)).toList();
        Order order  = Order.create(input.customerId(), lines);
        Order saved  = orderGateway.save(order);
        return new CreateOrderOutputData(saved.getId(), saved.getCustomerId(),
                saved.getStatus().name());
    }
}
```

---

## 3. Adapter Ring (Controllers + Gateways)

```java
// adapter/controller/OrderController.java
@Path("/orders")
public class OrderController {

    @Inject CreateOrderInputBoundary createOrder;

    @POST
    public Response create(@Valid CreateOrderRequest request) {
        CreateOrderOutputData output = createOrder.execute(
                new CreateOrderInputData(request.customerId(), request.productIds()));
        return Response.status(201).entity(output).build();
    }
}
public record CreateOrderRequest(@NotBlank String customerId,
                                 @NotEmpty List<String> productIds) {}
```

```java
// adapter/gateway/OrderJpaGateway.java
@ApplicationScoped
public class OrderJpaGateway implements OrderGateway {

    @Inject OrderJpaRepository jpaRepo;

    @Override
    @Transactional
    public Order save(Order order) {
        OrderJpaEntity entity = OrderJpaMapper.toEntity(order);
        jpaRepo.persist(entity);
        return OrderJpaMapper.toDomain(entity);
    }

    @Override
    public Optional<Order> findById(Long id) {
        return jpaRepo.findByIdOptional(id).map(OrderJpaMapper::toDomain);
    }
}
```

---

## 4. Exception Handling

```java
// framework/exception/BusinessRuleViolationMapper.java
@Provider
public class BusinessRuleViolationMapper implements ExceptionMapper<BusinessRuleViolation> {
    @Override
    public Response toResponse(BusinessRuleViolation ex) {
        return Response.status(422)
                .entity(new ErrorResponse(422, "APP-4221", "BusinessRuleViolation", ex.getMessage()))
                .build();
    }
}
```

---

## 5. Testing Strategy

```java
// Use case test — no Quarkus, no DB
class CreateOrderUseCaseTest {

    @Mock OrderGateway orderGateway;
    @InjectMocks CreateOrderUseCase useCase;

    @Test
    void execute_creates_order_successfully() {
        when(orderGateway.save(any())).thenAnswer(inv -> inv.getArgument(0));
        CreateOrderOutputData result = useCase.execute(
                new CreateOrderInputData("c1", List.of("p1")));
        assertThat(result.status()).isEqualTo("PENDING");
    }
}

// Entity test — pure Java
class OrderTest {
    @Test
    void approve_fails_when_not_pending() {
        Order order = Order.create("c1", List.of(new OrderLine("p1", 1)));
        order.approve();
        assertThatThrownBy(order::approve)
                .isInstanceOf(BusinessRuleViolation.class);
    }
}
```

**Coverage: ≥ 80%** — focus on entity and use case rings (highest business value).

---

## Pre-commit Checklist

- [ ] **[CRITICAL]** Entity ring classes have zero imports from `jakarta.*` or `quarkus.*`
- [ ] **[CRITICAL]** Use case ring classes depend only on entity ring and port interfaces — no adapter imports
- [ ] **[CRITICAL]** Global exception handler present — `BusinessRuleViolationMapper` maps domain exceptions without leaking stack traces
- [ ] **[HIGH]** Every use case has a named input boundary interface (`CreateOrderInputBoundary`)
- [ ] **[HIGH]** Every use case has a named output data record (`CreateOrderOutputData`) — no entity leakage to adapters
- [ ] **[HIGH]** Coverage ≥ 80% with focus on entity and use case rings
- [ ] **[HIGH]** Flyway migrations used — `database.generation=none` in production
- [ ] **[MEDIUM]** OpenAPI annotations present on all adapter/controller endpoints
- [ ] **[MEDIUM]** Outbox pattern applied for any use case that publishes domain events
- [ ] **[LOW]** ADR (Architecture Decision Record) documents why Clean Architecture was chosen over Hexagonal
