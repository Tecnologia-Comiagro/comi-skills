---
name: quarkus-cqrs
description: Scaffold or extend a Quarkus project using CQRS (Command Query Responsibility Segregation). Use when read and write loads differ significantly, when reporting queries are complex, or when write operations require strict consistency while reads can be eventually consistent.
argument-hint: "[action: scaffold|add-command|add-query|add-projection] [name?]"
metadata:
  short-description: Quarkus CQRS — separate command and query models
---

You are working on a Quarkus project using **CQRS (Command Query Responsibility Segregation)**. Apply all patterns below. Read existing code before making changes.

---

## When to Use This Architecture

| Use CQRS when... | Avoid when... |
|-----------------|---------------|
| Read/write load is asymmetric | Simple CRUD with equal load |
| Reporting queries are complex joins | Small team / fast prototype |
| Write side needs strict consistency | No scalability requirements |
| Read side can be eventually consistent | Single data model is sufficient |
| Domain events drive projections | Overkill for simple domains |

**Compared to other architectures:**
- Extends **Hexagonal/Clean** — commands go through the write stack, queries bypass it
- More complex than **Layered** — two models, two stacks
- Often combined with **Event Sourcing** for full auditability

---

## Directory Structure

```
src/main/java/com/comiagro/app/
├── command/                     # Write side — strict consistency
│   ├── handler/                 # Command handlers (one per command)
│   ├── model/                   # Write-side domain entities
│   ├── port/
│   │   ├── in/                  # Command interfaces
│   │   └── out/                 # Write repository interfaces
│   └── exception/               # Domain exceptions
├── query/                       # Read side — optimized for reads
│   ├── handler/                 # Query handlers
│   ├── model/                   # Read models / projections (flat, denormalized)
│   └── port/
│       ├── in/                  # Query interfaces
│       └── out/                 # Read repository interfaces
├── infrastructure/
│   ├── persistence/
│   │   ├── write/               # JPA entities + write repos (normalized)
│   │   └── read/                # Read repos (views, projections, optional separate DB)
│   ├── messaging/               # Domain events → projections
│   └── exception/               # GlobalExceptionMapper
└── api/                         # REST resources — routes commands and queries
```

---

## 1. Command Side (Write)

```java
// command/port/in/CreateOrderCommand.java
public record CreateOrderCommand(String customerId, List<String> productIds) {}

// command/port/in/CreateOrderCommandHandler.java
public interface CreateOrderCommandHandler {
    Long handle(CreateOrderCommand command);   // returns aggregate ID
}
```

```java
// command/handler/CreateOrderHandler.java
@ApplicationScoped
public class CreateOrderHandler implements CreateOrderCommandHandler {

    @Inject WriteOrderRepository writeRepo;
    @Inject OrderEventPublisher  eventPublisher;

    @Override
    @Transactional
    public Long handle(CreateOrderCommand cmd) {
        if (cmd.productIds().isEmpty())
            throw new DomainException("Order must have products", DomainErrorCode.INVALID_INPUT);

        Order order = Order.create(cmd.customerId(), cmd.productIds());
        Order saved = writeRepo.save(order);

        // publish event → async projection update
        eventPublisher.publish(new OrderCreatedEvent(saved.getId(), saved.getCustomerId()));
        return saved.getId();
    }
}
```

---

## 2. Query Side (Read)

```java
// query/port/in/GetOrderQuery.java
public record GetOrderQuery(Long orderId) {}

// query/model/OrderSummary.java — flat, denormalized read model
public record OrderSummary(
    Long id, String customerId, String status,
    int totalItems, BigDecimal totalAmount, Instant createdAt
) {}
```

```java
// query/handler/GetOrderQueryHandler.java
@ApplicationScoped
public class GetOrderQueryHandler {

    @Inject ReadOrderRepository readRepo;

    public OrderSummary handle(GetOrderQuery query) {
        return readRepo.findSummaryById(query.orderId())
                .orElseThrow(() -> new DomainException(
                        "Order not found: " + query.orderId(), DomainErrorCode.NOT_FOUND));
    }

    public PageResult<OrderSummary> handleList(String customerId, PageRequest page) {
        return readRepo.findSummariesByCustomer(customerId, page);
    }
}
```

```java
// infrastructure/persistence/read/ReadOrderRepository.java
@ApplicationScoped
public class ReadOrderRepository {

    @Inject EntityManager em;

    public Optional<OrderSummary> findSummaryById(Long id) {
        // optimized native query or view — no domain model involved
        return em.createNativeQuery("""
                SELECT o.id, o.customer_id, o.status,
                       COUNT(ol.id) as total_items,
                       SUM(ol.price) as total_amount,
                       o.created_at
                FROM orders o LEFT JOIN order_lines ol ON ol.order_id = o.id
                WHERE o.id = :id GROUP BY o.id
                """, OrderSummaryProjection.class)
                .setParameter("id", id)
                .getResultStream().findFirst()
                .map(this::toSummary);
    }
}
```

---

## 3. Projection Updates (Event-Driven)

```java
// infrastructure/messaging/OrderProjectionUpdater.java
@ApplicationScoped
public class OrderProjectionUpdater {

    @Inject ReadOrderRepository readRepo;

    @Incoming("order-events")
    @Transactional
    public void on(OrderCreatedEvent event) {
        // denormalize and upsert into read model table
        readRepo.upsert(new OrderReadEntity(event.orderId(), event.customerId(), "PENDING", 0, BigDecimal.ZERO));
    }
}
```

---

## 4. REST API (Routes Commands and Queries)

```java
// api/OrderResource.java
@Path("/orders")
public class OrderResource {

    @Inject CreateOrderCommandHandler commandHandler;
    @Inject GetOrderQueryHandler      queryHandler;

    // COMMAND endpoint — returns 201 with Location header
    @POST
    public Response create(@Valid CreateOrderRequest request) {
        Long id = commandHandler.handle(
                new CreateOrderCommand(request.customerId(), request.productIds()));
        return Response.status(201)
                .header("Location", "/orders/" + id)
                .entity(Map.of("id", id))
                .build();
    }

    // QUERY endpoint — reads from the read model
    @GET
    @Path("/{id}")
    public OrderSummary get(@PathParam("id") Long id) {
        return queryHandler.handle(new GetOrderQuery(id));
    }

    @GET
    public PageResult<OrderSummary> list(
            @QueryParam("customerId") String customerId,
            @QueryParam("page") @DefaultValue("0") int page,
            @QueryParam("size") @DefaultValue("20") int size) {
        return queryHandler.handleList(customerId, new PageRequest(page, size));
    }
}
```

---

## 5. Exception Handling

Same pattern as `quarkus-hexagonal`:
- `DomainErrorCode` enum with `httpStatus`
- `DomainException` base class
- `DomainExceptionMapper` (`@Provider`) — closed for modification

---

## 6. Testing Strategy

```java
// Command handler test — mock write repo and event publisher
class CreateOrderHandlerTest {
    @Mock WriteOrderRepository writeRepo;
    @Mock OrderEventPublisher eventPublisher;
    @InjectMocks CreateOrderHandler handler;

    @Test
    void handle_saves_and_publishes_event() {
        var saved = new Order(1L, "c1", List.of("p1"));
        when(writeRepo.save(any())).thenReturn(saved);
        Long id = handler.handle(new CreateOrderCommand("c1", List.of("p1")));
        assertThat(id).isEqualTo(1L);
        verify(eventPublisher).publish(any(OrderCreatedEvent.class));
    }
}

// Query handler test — mock read repo
class GetOrderQueryHandlerTest {
    @Mock ReadOrderRepository readRepo;
    @InjectMocks GetOrderQueryHandler handler;

    @Test
    void handle_returns_summary() {
        var summary = new OrderSummary(1L, "c1", "PENDING", 1, BigDecimal.TEN, Instant.now());
        when(readRepo.findSummaryById(1L)).thenReturn(Optional.of(summary));
        assertThat(handler.handle(new GetOrderQuery(1L))).isEqualTo(summary);
    }
}
```

**Coverage: ≥ 80%** — command handlers and query handlers are the critical paths.

---

## Known Gotchas

**Eventual consistency** — after a POST, an immediate GET may return stale data if the projection hasn't updated yet. Design the client to handle this (polling, optimistic UI).

**Two write targets** — command handler writes to the normalized write model; projection updater writes to the read model. Use the **Outbox Pattern** to guarantee both succeed.

**Don't query the write model** — the read side has its own repository. Never inject `WriteOrderRepository` into a query handler.
