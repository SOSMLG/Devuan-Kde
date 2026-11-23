# Devuan KDE - Makefile
#
# Small convenience targets for release checks, step listings and archives.
# The installer itself is driven by ./install.sh.

SHELL   := /usr/bin/env bash
REPO    := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
VERSION := $(shell tr -d '[:space:]' < $(REPO)/VERSION 2>/dev/null || echo unknown)
STEP_COUNT := $(shell ls $(REPO)/scripts/[0-9][0-9]-*.sh 2>/dev/null | wc -l | tr -d ' ')

.DEFAULT_GOAL := help
.PHONY: help release-preflight dist list list-utilities version count clean

## help: show this help
help:
	@echo "Devuan KDE $(VERSION) - $(STEP_COUNT) steps"
	@echo
	@echo "  make release-preflight  check VERSION/RELEASE.md before tagging"
	@echo "  make dist               build the uploadable archive in dist/"
	@echo "  make list               list runnable steps"
	@echo "  make list-utilities     list standalone utilities"
	@echo "  make version            print VERSION"
	@echo
	@echo "The scripts themselves are NOT driven by make - use ./install.sh --help"

## version: print the current version
version:
	@echo $(VERSION)

## count: number of step scripts
count:
	@echo $(STEP_COUNT)

## release-preflight: checks before a tag
release-preflight:
	@bash -n $(REPO)/install.sh $(REPO)/scripts/lib/runner.sh
	@test -f $(REPO)/VERSION || { echo "FAIL: no VERSION"; exit 1; }
	@grep -q '$(VERSION)' $(REPO)/RELEASE.md || { echo "FAIL: RELEASE.md does not mention $(VERSION)"; exit 1; }
	@bash $(REPO)/install.sh --list >/dev/null
	@bash $(REPO)/install.sh --list-utilities >/dev/null
	@echo "preflight OK for $(VERSION)"

## dist: build the uploadable archive in dist/ (no network, no root)
dist:
	@mkdir -p $(REPO)/dist
	@out=$(REPO)/dist/devuan-kde-setup-$(VERSION).tar.gz; \
	rm -f "$$out"; \
	listf=$$(mktemp); trap 'rm -f "$$listf"' EXIT; \
	(cd $(REPO) && git ls-files -z --cached --others --exclude-standard \
	    | grep -zv '^dist/' > "$$listf"); \
	if [ ! -s "$$listf" ]; then echo "FAIL: no files to archive"; exit 1; fi; \
	(cd $(REPO) && tar --null --ignore-failed-read -czf "$$out" \
	    --exclude='.git' --exclude='dist' --exclude='*.swp' --exclude='*~' \
	    --exclude='.DS_Store' \
	    --transform 's,^,devuan-kde-setup-$(VERSION)/,' -T "$$listf"); \
	if [ ! -s "$$out" ]; then echo "FAIL: empty archive"; exit 1; fi; \
	untracked=$$(cd $(REPO) && git ls-files --others --exclude-standard | wc -l); \
	echo "built $$out ($$(du -h "$$out" | cut -f1), $$(tar -tzf "$$out" | wc -l) files)"; \
	if [ "$$untracked" -gt 0 ]; then \
	    echo "note: $$untracked untracked file(s) included (not yet committed)"; \
	fi

## list: list runnable steps
list:
	@bash $(REPO)/install.sh --list

## list-utilities: list standalone utilities
list-utilities:
	@bash $(REPO)/install.sh --list-utilities

## clean: remove generated scratch files
clean:
	@rm -rf /tmp/devmkde-* 2>/dev/null || true
	@echo "cleaned scratch files"
