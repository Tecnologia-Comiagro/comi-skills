---
name: quarkus-layered
description: Scaffold or extend a Quarkus project using Layered (N-Tier) Architecture. Use when the project is a CRUD service, internal tool, or small microservice where simplicity and fast delivery matter more than domain complexity.
license: MIT
argument-hint: "[action: scaffold|add-layer|add-endpoint] [name?]"
metadata:
  short-description: Quarkus Layered (N-Tier) Architecture — CRUD & simple services
  version: "1.1.0"
  author: jorge.reyes@comiagro.com
---

You are working on a Quarkus project using **Layered (N-Tier) Architecture**. Apply all patterns below. Read existing code before making changes.

## When to Apply

- Building a **CRUD service**, internal tool, or MVP where speed of delivery matters
- The domain has no complex business rules — mostly data in, data out
- Adding an endpoint, service method, or repository to a layered Quarkus project
- Small team or solo developer — minimal boilerplate is a priority
- Prototyping a feature before deciding on a more complex architecture
- The user asks for a "simple REST API" without specifying architecture

---

## When to Use This Architecture

| Use Layered when... | Avoid Layered when... |
|--------------------|-----------------------|
| Simple CRUD operations | Complex business rules |
| Internal tools / back-office | Multiple external integrations |
| Small team, fast delivery | Long-lived enterprise system |
| Data-centric service | Rich domain model needed |
| Prototype or MVP | CQRS or event-sourcing required |

**Compared to other architectures:**
- Simpler than **Hexagonal** — no ports/adapters abstraction
- Less strict than **Clean Architecture** — no use case ring
- More structured than **Vertical Slice** — shared layers across features

---

## Directory Structure

```
src/main/java/com/comiagro/app/
├── controller/          # REST layer — HTTP in/out, validation, mapping
│   └── dto/             # Request/Response DTOs (records)
├── service/             # Business logic — orchestration and rules
├── repository/          # Data access — Panache repositories
│   └── entity/          # JPA @Entity classes
└── exception/           # Global exception handling
    ├── AppException.java
    ├── AppErrorCode.java
    └── GlobalExceptionMapper.java
```

**Dependency flow — one direction only:**
```
Controller → Service → Repository → DB
```

- `Controller` never calls `Repository` directly
- `Service` never handles HTTP concerns
- `Repository` never contains business logic

---

## 1. Exception Pattern

```java
// exception/AppErrorCode.java
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
```

```java
// exception/AppException.java
public class AppException extends RuntimeException {
    public final AppErrorCode errorCode;
    public AppException(String message, AppErrorCode errorCode) {
        super(message); this.errorCode = errorCode;
    }
}
```

```java
// exception/GlobalExceptionMapper.java
@Provider
public class GlobalExceptionMapper implements ExceptionMapper<AppException> {
    private static final Logger LOG = Logger.getLogger(GlobalExceptionMapper.class);

    @Override
    public Response toResponse(AppException ex) {
        LOG.warnf("[%s] %s", ex.errorCode.code, ex.getMessage());
        return Response.status(ex.errorCode.httpStatus)
                .entity(new ErrorResponse(ex.errorCode.httpStatus, ex.errorCode.code,
                        ex.getClass().getSimpleName(), ex.getMessage()))
                .build();
    }
}
public record ErrorResponse(int statusCode, String errorCode, String error, String message) {}
```

---

## 2. Repository Layer (Panache)

```java
// repository/entity/OrderEntity.java
@Entity
@Table(name = "orders")
public class OrderEntity extends PanacheEntityBase {
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    public Long id;
    public String customerId;
    public String status;
    public Instant createdAt = Instant.now();
}
```

```java
// repository/OrderRepository.java
@ApplicationScoped
public class OrderRepository implements PanacheRepository<OrderEntity> {

    public Optional<OrderEntity> findByIdOptional(Long id) {
        return find("id", id).firstResultOptional();
    }

    public List<OrderEntity> findByCustomer(String customerId, int page, int size) {
        return find("customerId", customerId)
                .page(page, size).list();
    }
}
```

---

## 3. Service Layer

```java
// service/OrderService.java
@ApplicationScoped
public class OrderService {

    @Inject OrderRepository repository;

    @Transactional
    public OrderEntity create(String customerId, List<String> items) {
        if (items == null || items.isEmpty()) {
            throw new AppException("Items cannot be empty", AppErrorCode.INVALID_INPUT);
        }
        OrderEntity order = new OrderEntity();
        order.customerId = customerId;
        order.status     = "PENDING";
        repository.persist(order);
        return order;
    }

    public OrderEntity findById(Long id) {
        return repository.findByIdOptional(id)
                .orElseThrow(() -> new AppException("Order not found: " + id, AppErrorCode.NOT_FOUND));
    }

    public List<OrderEntity> findByCustomer(String customerId, int page, int size) {
        return repository.findByCustomer(customerId, page, size);
    }
}
```

---

## 4. Controller Layer

```java
// controller/OrderController.java
@Path("/orders")
@Produces(MediaType.APPLICATION_JSON)
@Consumes(MediaType.APPLICATION_JSON)
@Tag(name = "Orders")
public class OrderController {

    @Inject OrderService orderService;

    @POST
    @Operation(summary = "Create order")
    @APIResponse(responseCode = "201", description = "Order created")
    public Response create(@Valid CreateOrderRequest request) {
        OrderEntity order = orderService.create(request.customerId(), request.items());
        return Response.status(201).entity(OrderMapper.toResponse(order)).build();
    }

    @GET
    @Path("/{id}")
    @Operation(summary = "Get order by ID")
    public OrderResponse findById(@PathParam("id") Long id) {
        return OrderMapper.toResponse(orderService.findById(id));
    }
}
```

```java
// controller/dto/CreateOrderRequest.java
public record CreateOrderRequest(
    @NotBlank String customerId,
    @NotEmpty List<String> items
) {}

// controller/dto/OrderResponse.java
public record OrderResponse(Long id, String customerId, String status, Instant createdAt) {}
```

```java
// controller/OrderMapper.java
final class OrderMapper {
    private OrderMapper() {}
    static OrderResponse toResponse(OrderEntity e) {
        return new OrderResponse(e.id, e.customerId, e.status, e.createdAt);
    }
}
```

---

## 5. Testing Strategy

### Service Unit Tests (Mockito)

```java
@ExtendWith(MockitoExtension.class)
class OrderServiceTest {

    @Mock OrderRepository repository;
    @InjectMocks OrderService service;

    @Test
    void create_fails_when_items_empty() {
        assertThatThrownBy(() -> service.create("c1", List.of()))
                .isInstanceOf(AppException.class)
                .hasMessageContaining("Items cannot be empty");
    }

    @Test
    void findById_throws_when_not_found() {
        when(repository.findByIdOptional(99L)).thenReturn(Optional.empty());
        assertThatThrownBy(() -> service.findById(99L))
                .isInstanceOf(AppException.class);
    }
}
```

### Controller Integration Tests (@QuarkusTest)

```java
@QuarkusTest
class OrderControllerTest {

    @InjectMock OrderService orderService;

    @Test
    void post_returns_201() {
        when(orderService.create(any(), any())).thenReturn(mockEntity());
        given().contentType(ContentType.JSON)
               .body("""{"customerId":"c1","items":["p1"]}""")
        .when().post("/orders")
        .then().statusCode(201);
    }

    @Test
    void get_returns_404_when_not_found() {
        when(orderService.findById(99L))
                .thenThrow(new AppException("Not found", AppErrorCode.NOT_FOUND));
        given().when().get("/orders/99")
               .then().statusCode(404).body("errorCode", equalTo("APP-4041"));
    }
}
```

**Coverage requirement: ≥ 80%** (JaCoCo — same config as quarkus-hexagonal skill)

---

## 6. DB Migrations (Flyway)

Same as `quarkus-hexagonal` skill — see section 18 there.

---

## Known Gotchas

**`@Transactional` placement** — annotate `service` methods, never controller methods.

**DTO vs Entity leakage** — never return `OrderEntity` from the controller — always map to `OrderResponse`.

**Anemic service** — if the service is only `repository.save(entity)`, reconsider — business logic belongs in the service, not scattered in the controller.

**When to migrate to Hexagonal** — when you find yourself adding `if (source.equals("kafka"))` branches in a service, it's time to introduce ports.

---

## Pre-commit Checklist

- [ ] **[CRITICAL]** Global exception handler (`GlobalExceptionMapper`) is present — no raw exceptions exposed to clients
- [ ] **[CRITICAL]** `@Transactional` is on service methods only — never on controller methods
- [ ] **[HIGH]** Controller returns DTOs (`OrderResponse`), never JPA entities (`OrderEntity`)
- [ ] **[HIGH]** Coverage ≥ 80% enforced via JaCoCo (service unit tests + controller integration tests)
- [ ] **[HIGH]** Flyway migrations used — `quarkus.hibernate-orm.database.generation=none` in production
- [ ] **[MEDIUM]** OpenAPI annotations (`@Operation`, `@APIResponse`) on all endpoints
- [ ] **[MEDIUM]** `@ConfigMapping` used for typed config — no raw `@ConfigProperty` for complex config
- [ ] **[LOW]** Health checks (`@Readiness`, `@Liveness`) configured via SmallRye Health
