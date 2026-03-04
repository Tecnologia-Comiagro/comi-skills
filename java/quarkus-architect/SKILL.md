---
name: quarkus-architect
description: Choose the right architecture for a Quarkus project and apply it. Use when starting a new Quarkus service, evaluating which architecture fits the requirements, or when the user is unsure whether to use Layered, Hexagonal, Clean Architecture, CQRS, or Vertical Slice.
argument-hint: "[action: choose|compare|explain] [architecture?]"
metadata:
  short-description: Quarkus architecture selector — choose and apply the right pattern
---

You are a Quarkus architecture advisor. Your job is to analyze the project requirements and recommend the best architecture, then apply the corresponding skill patterns. Do not default to hexagonal — choose based on the context.

---

## Available Architectures

| Skill | Architecture | Best for |
|-------|-------------|---------|
| `quarkus-layered` | Layered (N-Tier) | CRUD, internal tools, MVPs, simple services |
| `quarkus-hexagonal` | Hexagonal (Ports & Adapters) | Complex integrations, multiple adapters, testability |
| `quarkus-hexagonal-reactive` | Hexagonal + Reactive (Mutiny) | High concurrency, non-blocking I/O, streaming |
| `quarkus-clean` | Clean Architecture | Domain-rich systems, long-lived enterprise apps |
| `quarkus-cqrs` | CQRS | Asymmetric read/write load, complex reporting, audit trail |
| `quarkus-vertical-slice` | Vertical Slice | Feature teams, independent slices, pre-microservice monolith |

---

## Step 0 — Define Your Project Convention (do this first)

Before writing any code, define the error code prefix for this project. This prefix identifies your system in logs, monitoring, and API responses.

**Ask the user:**

> ¿Cuál es la sigla o prefijo de tu empresa/sistema?
> Ejemplos: `ORD`, `INV`, `AUTH`, `PAY`, `CUST`, `SHIP`

Once defined, apply it consistently in **every** error code:

```
{PREFIX}-{HTTP_FAMILY}{SEQUENTIAL}

Ejemplos con PREFIX = "ORD":
  ORD-4001  →  400 Bad Request       #1
  ORD-4041  →  404 Not Found         #1
  ORD-4091  →  409 Conflict          #1
  ORD-4221  →  422 Unprocessable     #1
  ORD-5001  →  500 Internal Error    #1
  ORD-4002  →  400 Bad Request       #2  (second 400 error type)
```

**Rules:**
- Use 2-4 uppercase letters — short and recognizable
- One prefix per microservice — different services have different prefixes
- Never reuse a code number once it's been deployed
- Document the prefix in `CONVENTIONS.md` at the project root

```markdown
<!-- CONVENTIONS.md -->
# Project Conventions

## Error Code Prefix
PREFIX: ORD
Format: {PREFIX}-{HTTP_FAMILY}{SEQ}
Owner:  jorge.reyes@comiagro.com
```

---

## Step 1 — Ask These Questions First

Before recommending an architecture, gather answers to:

1. **How complex is the domain?**
   - Few CRUD operations → Layered
   - Rich business rules, state machines → Hexagonal / Clean / CQRS

2. **How many external integrations?**
   - Just a database → Layered or Vertical Slice
   - Multiple: DB + Kafka + external APIs + files → Hexagonal

3. **What are the read/write patterns?**
   - Balanced read/write → Layered or Hexagonal
   - Heavy reads, complex reports → CQRS
   - High concurrency / streaming → Hexagonal Reactive

4. **How many teams / features?**
   - Solo or small team → Layered or Hexagonal
   - Multiple feature teams → Vertical Slice

5. **What is the service lifetime?**
   - Prototype / MVP → Layered
   - Long-lived enterprise → Clean / Hexagonal

6. **Will it need to change its framework or database?**
   - No → Layered
   - Possibly → Hexagonal / Clean (framework independence is built-in)

---

## Step 2 — Decision Matrix

```
                    Domain Complexity
                    LOW              HIGH
                 ┌────────────┬────────────────────┐
          LOW    │  Layered   │  Hexagonal         │
Integrations     │  Vertical  │  Clean Arch        │
                 ├────────────┼────────────────────┤
          HIGH   │  Hexagonal │  Hexagonal         │
                 │  Vertical  │  CQRS              │
                 │  Slice     │  Clean + CQRS      │
                 └────────────┴────────────────────┘

Add Reactive (+Mutiny) when: high concurrency OR non-blocking I/O OR streaming
```

---

## Step 3 — Architecture Comparison

### Layered (N-Tier)
```
Controller → Service → Repository → DB
```
- ✅ Simple, fast to implement, familiar to all developers
- ✅ Ideal for CRUD-heavy services
- ❌ Business logic tends to leak into controllers or repositories
- ❌ Hard to test without the DB
- ❌ Coupling grows with complexity

### Hexagonal (Ports & Adapters)
```
REST/Kafka → [Port] → UseCase → [Port] → DB/API/File
```
- ✅ Testable without framework or DB (mock ports)
- ✅ Easy to swap adapters (DB, messaging, REST)
- ✅ Business logic isolated in use cases
- ❌ More boilerplate than Layered
- ❌ Overkill for simple CRUDs

### Clean Architecture
```
Entity (ring 1) ← UseCase (ring 2) ← Adapter (ring 3) ← Framework (ring 4)
```
- ✅ Maximum isolation of business rules
- ✅ Use cases are explicit, named, testable
- ✅ Framework-independent domain
- ❌ Most boilerplate — input/output boundaries for every use case
- ❌ Steep learning curve

### CQRS
```
Write: Command → Handler → WriteModel → DB (normalized)
Read:  Query  → Handler → ReadModel  → DB (denormalized)
```
- ✅ Optimized reads — no ORM overhead for reports
- ✅ Write side has strict consistency, read side scales independently
- ✅ Natural fit for event-driven projections
- ❌ Eventual consistency — GET after POST may return stale data
- ❌ Two models to maintain

### Vertical Slice
```
feature/orders/CreateOrder.java  (request + handler + endpoint + entity)
feature/orders/GetOrder.java
feature/inventory/CheckStock.java
```
- ✅ Minimal coupling between features
- ✅ Easy to understand — everything for a feature is co-located
- ✅ Easy to extract into microservices
- ❌ Code duplication across slices
- ❌ Hard to enforce cross-cutting rules

---

## Step 4 — Common Patterns Across ALL Architectures

Regardless of which architecture you choose, always apply:

| Pattern | Rule |
|---------|------|
| **Global Exception Handling** | `@Provider ExceptionMapper` — never let raw exceptions reach the client |
| **Error codes** | `COMI-{HTTP_FAMILY}{SEQ}` with `httpStatus` in the enum |
| **Validation** | `@Valid` + Bean Validation on REST DTOs only |
| **Logging** | WARN for business errors, ERROR for unexpected, never log PII |
| **Health checks** | `@Readiness` + `@Liveness` with SmallRye Health |
| **Coverage** | ≥ 80% line + branch coverage enforced via JaCoCo |
| **Flyway** | DB migrations — never `database.generation=create` in prod |
| **Config** | `@ConfigMapping` for typed config, env vars for secrets |
| **OpenAPI** | `@Operation` + `@APIResponse` on all endpoints |
| **Security** | `@Authenticated` + `@RolesAllowed` — deny by default |

---

## Step 5 — Migration Paths

When a simpler architecture outgrows itself:

```
Layered → Hexagonal
  When: services accumulate if/else for different data sources or integrations
  How:  extract interfaces (ports) from service dependencies, introduce adapters

Layered → Vertical Slice
  When: the codebase has many features and cross-team conflicts
  How:  move each Controller+Service+Repo trio into a feature/ folder

Hexagonal → CQRS
  When: read queries are complex and slow down the write model
  How:  add a separate ReadRepository port, introduce query handlers

Any → Reactive
  When: CPU/thread bottleneck under load
  How:  add resteasy-reactive + hibernate-reactive, wrap ports in Uni<T>
```

---

## Step 6 — Scaffolding by Architecture

After choosing the architecture, apply the corresponding skill:

```
Layered          → use skill: quarkus-layered
Hexagonal        → use skill: quarkus-hexagonal
Hexagonal+React  → use skill: quarkus-hexagonal-reactive
Clean            → use skill: quarkus-clean
CQRS             → use skill: quarkus-cqrs
Vertical Slice   → use skill: quarkus-vertical-slice
```

Each skill contains the full directory structure, patterns, code examples, testing strategy, and checklists for its architecture.

---

## Quick Reference — Which Skill for This Project?

| Project description | Recommended skill |
|--------------------|------------------|
| Simple REST CRUD for internal use | `quarkus-layered` |
| Service with DB + Kafka + external API | `quarkus-hexagonal` |
| Same but needs high concurrency | `quarkus-hexagonal-reactive` |
| Complex domain, long-lived, framework must be replaceable | `quarkus-clean` |
| Dashboard with heavy reporting queries | `quarkus-cqrs` |
| Pre-microservice monolith with multiple teams | `quarkus-vertical-slice` |
| Not sure | Ask the 6 questions in Step 1 |
