---
name: skills-updater
description: Review, validate and update skills in the comi-skills repository. Use when the user wants to update a skill to a new framework version, add missing patterns, check for outdated code, audit breaking changes, or run the periodic skill maintenance checklist.
argument-hint: "[action: audit|update-versions|add-section|breaking-changes] [skill-name?]"
metadata:
  short-description: Keep comi-skills up to date with latest versions and patterns
---

You are the maintainer of the **comi-skills** repository. Your job is to keep every skill accurate, up to date, and complete. Apply the process below before making any changes.

---

## Repository Structure

```
comi-skills/
├── java/
│   ├── quarkus/SKILL.md               → quarkus-hexagonal
│   └── quarkus-reactive/SKILL.md      → quarkus-hexagonal-reactive
├── javascript/
│   └── react/SKILL.md                 → (pending)
├── dark/
│   └── flutter/SKILL.md               → flutter-ui
├── meta/
│   └── skills-updater/SKILL.md        → this skill
├── Makefile                           → install both agents
├── Makefile.claude                    → install Claude only
├── Makefile.codex                     → install Codex only
└── README.md
```

Install after any change:
```bash
make install                          # both agents
make install SKILL=<name>             # one skill only
```

---

## 1. Periodic Audit Checklist

Run this checklist **once per quarter** or after a major framework release.

### 1.1 Version Check

```bash
# Check latest Quarkus version
curl -s https://api.github.com/repos/quarkusio/quarkus/releases/latest | grep tag_name

# Check Quarkus extension catalog
quarkus ext list --installable | grep <extension-name>
```

For each Quarkus skill, verify:
- [ ] `quarkus-maven-plugin` version in scaffolding section is current
- [ ] All extension names match the current Quarkus catalog (names change between major versions)
- [ ] `application.properties` keys are valid (keys are renamed in major versions)
- [ ] JDK version in Dockerfiles matches the current LTS (Java 21 as of 2025)
- [ ] `FROM` base images in Dockerfiles are not end-of-life

### 1.2 Pattern Validity Check

For each code example in a skill, verify:
- [ ] Imports still exist in the current version
- [ ] Annotations haven't been renamed or moved (`@WithTransaction` was added in Quarkus 2.x)
- [ ] Deprecated APIs replaced with current equivalents
- [ ] Test APIs (`UniAssertSubscriber`, `@QuarkusTest`) still work as documented

### 1.3 Completeness Check

For each skill, verify coverage of:
- [ ] Project scaffolding (create from scratch)
- [ ] Core architecture patterns
- [ ] Exception handling (global, typed)
- [ ] Testing (unit, integration, coverage ≥ 80%)
- [ ] Value Objects / rich domain model
- [ ] Mapper pattern
- [ ] Logging conventions
- [ ] Health checks
- [ ] Pagination
- [ ] Security (JWT)
- [ ] Observability (metrics + tracing)
- [ ] DB migrations
- [ ] Config management
- [ ] Messaging / events
- [ ] Resilience patterns
- [ ] Containerization
- [ ] OpenAPI docs
- [ ] Idempotency
- [ ] Outbox pattern

---

## 2. Updating Extension Versions

When a new Quarkus major/minor version is released:

1. **Read the migration guide** at `https://quarkus.io/guides/migration-guide-{version}`
2. **Check for renamed extensions** — search for old name in all SKILL.md files
3. **Check for renamed properties** — Quarkus publishes a property migration table
4. **Update scaffolding commands** — bump the plugin version in section 0
5. **Update Dockerfile base images** if JDK version changed
6. **Run `make install`** and test manually with `quarkus create app`

```bash
# Find all version references in skills
grep -rn "3\.[0-9]\+\.[0-9]\+" . --include="*.md"

# Find all extension names to verify
grep -rn "quarkus-\|smallrye-\|resteasy-\|hibernate-" . --include="*.md" | grep "ext add\|<artifactId>"
```

---

## 3. Adding a New Section to an Existing Skill

1. Read the full SKILL.md before making changes
2. Check if the topic is already covered (partial coverage counts)
3. Follow the section numbering (`## N. Topic Name`)
4. Structure: intro sentence → code example → rules/gotchas
5. Add the reactive variant to `quarkus-hexagonal-reactive` if applicable
6. Update the checklist at the end of the skill
7. Run `make install SKILL=<name>`

Section template:
```markdown
## N. Topic Name

Brief explanation of what this is and why it matters.

```java
// path/to/File.java
// complete, runnable example with imports
```

**Rules:**
- Rule 1 — imperative, specific
- Rule 2 — what NOT to do
```

---

## 4. Breaking Changes Protocol

When a breaking change is detected:

```
1. Create a git branch: git checkout -b update/<skill>-<version>
2. Update the affected SKILL.md
3. Mark deprecated patterns with: > ⚠️ Deprecated in vX.Y — use NewPattern instead
4. Keep the old example commented out for 1 quarter, then remove
5. Run: make install SKILL=<name>
6. Commit: git commit -m "update(<skill>): migrate to Quarkus vX.Y"
```

Example deprecation notice:
```markdown
> ⚠️ **Quarkus 3.x**: `@Transactional` on reactive methods is deprecated.
> Use `@WithTransaction` instead (already updated above).
```

---

## 5. Adding a New Skill

1. Identify the framework and architecture style
2. Create the folder: `<language>/<skill-name>/SKILL.md`
3. Write the frontmatter:
   ```yaml
   ---
   name: <skill-name>
   description: <one-line trigger — be specific about when to use>
   argument-hint: "[action: scaffold|validate|add-module] [name?]"
   metadata:
     short-description: <short label for Codex>
   ---
   ```
4. Cover at minimum: scaffolding, architecture, patterns, testing, exception handling
5. Run `make install SKILL=<name>`
6. Update `README.md` skills table

---

## 6. Skill Quality Rules

Every skill must satisfy:

| Rule | Check |
|------|-------|
| **Specific trigger** | `description` uses "Use when..." with concrete scenarios |
| **No framework in domain** | Domain examples have zero framework imports |
| **Runnable examples** | All code blocks compile as-is (no `...` in critical parts) |
| **Complete imports** | At least the first example of each pattern has full imports |
| **Actionable rules** | "Rules" sections use imperative verbs, not vague advice |
| **Coverage enforced** | Testing section includes JaCoCo config with ≥80% gate |
| **Both agents** | `argument-hint` (Claude) and `metadata.short-description` (Codex) present |

---

## 7. Version Tracking

Keep this section updated after each audit:

| Skill | Last audited | Framework version | Next review |
|-------|-------------|------------------|-------------|
| `quarkus-hexagonal` | 2026-03 | Quarkus 3.9.5 / Java 21 | 2026-06 |
| `quarkus-hexagonal-reactive` | 2026-03 | Quarkus 3.9.5 / Java 21 | 2026-06 |
| `flutter-ui` | — | — | — |
| `nestjs-hexagonal` | — | NestJS 10.x | — |
