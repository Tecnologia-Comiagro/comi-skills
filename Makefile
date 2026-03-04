.PHONY: install install-claude install-codex \
        uninstall uninstall-claude uninstall-codex \
        list help

# ─────────────────────────────────────────────
# Install
# ─────────────────────────────────────────────

## install [SKILL=name]: Install for Claude + Codex. Omit SKILL to install all.
install: install-claude install-codex

## install-claude [SKILL=name]: Install for Claude Code only
install-claude:
	@$(MAKE) -f Makefile.claude install $(if $(SKILL),SKILL=$(SKILL))

## install-codex [SKILL=name]: Install for OpenAI Codex only
install-codex:
	@$(MAKE) -f Makefile.codex install $(if $(SKILL),SKILL=$(SKILL))

# ─────────────────────────────────────────────
# Uninstall
# ─────────────────────────────────────────────

## uninstall [SKILL=name]: Remove from Claude + Codex. Omit SKILL to remove all.
uninstall: uninstall-claude uninstall-codex

## uninstall-claude [SKILL=name]: Remove from Claude Code only
uninstall-claude:
	@$(MAKE) -f Makefile.claude uninstall $(if $(SKILL),SKILL=$(SKILL))

## uninstall-codex [SKILL=name]: Remove from OpenAI Codex only
uninstall-codex:
	@$(MAKE) -f Makefile.codex uninstall $(if $(SKILL),SKILL=$(SKILL))

# ─────────────────────────────────────────────
# Info
# ─────────────────────────────────────────────

## list: Show install status in Claude and Codex
list:
	@echo ""
	@echo "Claude Code  (~/.claude/skills/)"
	@$(MAKE) -f Makefile.claude list
	@echo ""
	@echo "OpenAI Codex  (~/.codex/skills/)"
	@$(MAKE) -f Makefile.codex list

## help: Show available targets
help:
	@grep -E '^## ' Makefile | sed 's/## /  /'
