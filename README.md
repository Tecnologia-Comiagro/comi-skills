# comi-skills

**Autor:** Jorge Ivan Reyes Valencia — jorge.reyes@comiagro.com
**Empresa:** Comiagro S.A

Librería de skills compartida para **Claude Code** y **OpenAI Codex** en Comiagro.

Un skill es un archivo markdown que le da al agente de IA conocimiento especializado: patrones de arquitectura, convenciones de código, checklists y guías de flujo de trabajo. El desarrollador decide qué skills instala en su agente.

---

## Skills disponibles

### Java · Quarkus

| Skill | Arquitectura | Cuándo usar |
|-------|-------------|------------|
| `quarkus-architect` | Selector | No sabes cuál elegir — analiza requisitos y recomienda |
| `quarkus-layered` | N-Tier | CRUD, herramientas internas, MVPs, servicios simples |
| `quarkus-hexagonal` | Hexagonal | Múltiples integraciones, alta testabilidad, imperativo |
| `quarkus-hexagonal-reactive` | Hexagonal + Mutiny | Alta concurrencia, I/O no bloqueante, streaming |
| `quarkus-clean` | Clean Architecture | Dominio rico, sistema de larga vida, independencia de framework |
| `quarkus-cqrs` | CQRS | Lecturas/escrituras asimétricas, reportes complejos |
| `quarkus-vertical-slice` | Vertical Slice | Equipos por feature, pre-microservicio |

### Meta

| Skill | Descripción |
|-------|------------|
| `skills-updater` | Auditoría, actualización de versiones y mantenimiento del repo |

---

## Estructura del repositorio

```
<lenguaje>/
└── <skill-name>/
    └── SKILL.md      ← frontmatter + cuerpo del skill
```

La carpeta es solo organización. El **nombre real del skill** (y del folder de instalación) viene del campo `name` en el frontmatter de cada `SKILL.md`.

---

## Flujo de trabajo

### 1. Ver qué skills hay disponibles

```bash
make list
```

```
Claude Code  (~/.claude/skills/)
SKILL                          SOURCE                        STATUS
─────                          ──────                        ──────
skills-updater                 meta/skills-updater           installed
quarkus-architect              java/quarkus-architect        installed
quarkus-layered                java/quarkus-layered          installed
quarkus-hexagonal              java/quarkus                  installed
quarkus-hexagonal-reactive     java/quarkus-reactive         installed
quarkus-clean                  java/quarkus-clean            installed
quarkus-cqrs                   java/quarkus-cqrs             installed
quarkus-vertical-slice         java/quarkus-vertical-slice   installed

OpenAI Codex  (~/.codex/skills/)
SKILL                          SOURCE                        STATUS
─────                          ──────                        ──────
skills-updater                 meta/skills-updater           installed
quarkus-architect              java/quarkus-architect        installed
...
```

### 2. Instalar un skill específico

```bash
# En ambos agentes
make install SKILL=quarkus-hexagonal

# Solo en Claude Code
make install-claude SKILL=quarkus-hexagonal

# Solo en OpenAI Codex
make install-codex SKILL=quarkus-hexagonal
```

### 3. Instalar todos los skills

```bash
make install           # Claude + Codex
make install-claude    # solo Claude
make install-codex     # solo Codex
```

### 4. Desinstalar

```bash
make uninstall SKILL=quarkus-hexagonal   # uno específico, ambos agentes
make uninstall-claude SKILL=quarkus-hexagonal
make uninstall                            # todos
```

---

## Paths de instalación

| Agente | Directorio |
|--------|-----------|
| Claude Code | `~/.claude/skills/<name>/SKILL.md` |
| OpenAI Codex | `~/.codex/skills/<name>/SKILL.md` |

---

## Crear un nuevo skill

1. Crear la carpeta `<lenguaje>/<skill-name>/`
2. Crear `SKILL.md` con el siguiente frontmatter:

```yaml
---
name: mi-skill                            # identificador único → nombre del folder instalado
description: >                            # cuándo se activa el skill (aparece en el system prompt)
  Descripción de una línea que describe cuándo usar este skill.
argument-hint: "[acción] [nombre?]"       # solo Claude Code
metadata:
  short-description: Etiqueta corta       # solo Codex
---

# Cuerpo del skill (markdown)
Patrones de arquitectura, reglas, ejemplos de código, checklists...
```

3. Instalar:

```bash
make install SKILL=mi-skill
```

---

## Referencia de comandos

| Comando | Descripción |
|---------|-------------|
| `make list` | Estado de instalación en Claude y Codex |
| `make install SKILL=name` | Instalar un skill en ambos agentes |
| `make install` | Instalar todos los skills en ambos agentes |
| `make install-claude SKILL=name` | Instalar un skill solo en Claude Code |
| `make install-codex SKILL=name` | Instalar un skill solo en OpenAI Codex |
| `make uninstall SKILL=name` | Desinstalar un skill de ambos agentes |
| `make uninstall` | Desinstalar todos los skills |
| `make uninstall-claude SKILL=name` | Desinstalar un skill solo de Claude |
| `make uninstall-codex SKILL=name` | Desinstalar un skill solo de Codex |

Los mismos targets están disponibles directamente en `Makefile.claude` y `Makefile.codex`:

```bash
make -f Makefile.claude install SKILL=quarkus-hexagonal
make -f Makefile.codex  install SKILL=quarkus-hexagonal
```
