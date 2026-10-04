# Devuan KDE — Makefile
#
# Thin wrapper around the test suite. The tests are plain bash and can always
# be run directly (`bash tests/run.sh`); the targets exist so the common
# invocations are one word and so CI and humans run the same thing.
#
# Everything under `make test` / `make check` is READ-ONLY: no root, no apt, no
# X, no network. Nothing here installs or removes anything.

SHELL   := /usr/bin/env bash
REPO    := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
PYTHON  ?= python3
VERSION := $(shell tr -d '[:space:]' < $(REPO)/VERSION 2>/dev/null || echo unknown)
STEP_COUNT := $(shell ls $(REPO)/scripts/[0-9][0-9]-*.sh 2>/dev/null | wc -l | tr -d ' ')

.DEFAULT_GOAL := help
.PHONY: help check test lint unit consistency apt-checks negative-controls \
        release-preflight dist list list-utilities version count clean

## help: show this help
help:
	@echo "Devuan KDE $(VERSION) — $(STEP_COUNT) steps"
	@echo
	@echo "  make check             run the full read-only test suite (tiers 1-3)"
	@echo "  make test              same as check"
	@echo "  make lint              tier 1: syntax + shellcheck (if present)"
	@echo "  make unit              tier 2: sandboxed unit tests"
	@echo "  make consistency       tier 3: cross-file consistency guards"
	@echo "  make apt-checks        tier 3: read-only apt-cache package existence"
	@echo "  make negative-controls prove each guard actually fails on its regression"
	@echo "  make release-preflight everything CI will check before tagging"
	@echo "  make list              list runnable steps"
	@echo "  make list-utilities    list standalone utilities"
	@echo "  make version           print VERSION"
	@echo
	@echo "The scripts themselves are NOT driven by make — use ./run.sh --help"

## version: print the current version
version:
	@echo $(VERSION)

## count: number of step scripts
count:
	@echo $(STEP_COUNT)

## lint: tier 1
lint:
	@bash $(REPO)/tests/lint.sh

## unit: tier 2
unit:
	@bash $(REPO)/tests/unit/run.sh

## consistency: tier 3 consistency guards
consistency:
	@bash $(REPO)/tests/consistency.sh

## apt-checks: tier 3 apt package existence
apt-checks:
	@bash $(REPO)/tests/apt-checks.sh

## negative-controls: inject each historical regression, require detection
negative-controls:
	@bash $(REPO)/tests/negative-controls.sh

## test / check: the whole read-only suite
test check:
	@bash $(REPO)/tests/run.sh
	@bash $(REPO)/tests/negative-controls.sh

## release-preflight: what CI checks before a tag
release-preflight:
	@bash $(REPO)/tests/run.sh
	@echo
	@echo "── release preflight extras ──"
	@bash -n $(REPO)/run.sh $(REPO)/install.sh
	@test -f $(REPO)/VERSION || { echo "FAIL: no VERSION"; exit 1; }
	@grep -q '$(VERSION)' $(REPO)/RELEASE.md || { echo "FAIL: RELEASE.md does not mention $(VERSION)"; exit 1; }
	@bash $(REPO)/run.sh --list >/dev/null
	@bash $(REPO)/run.sh --list-utilities >/dev/null
	@bash $(REPO)/scripts/verifySetup.sh >/dev/null 2>&1 \
		|| echo "note: verifySetup.sh reported unmet optional items (expected off-Plasma)"
	@echo "preflight OK for $(VERSION)"

## dist: build the uploadable archive in dist/ (no network, no root)
#
# One command so publishing does not need a hand-written file list. The file
# list is git's own view of the tree -- tracked files PLUS untracked files that
# .gitignore does not exclude -- minus dist/ itself. Two consequences, both
# deliberate:
#
#   * untracked-but-intended files ARE included, so `make dist` works before you
#     have committed. That is the whole point: the friction being removed is
#     hand-listing new files. .gitignore is what keeps scratch out.
#   * index entries whose file is gone are skipped (--ignore-failed-read), so a
#     `rm` that has not been `git add`ed yet cannot break the archive. tar would
#     otherwise abort with "Cannot stat" after writing a partial tarball, and the
#     target still reported success — the worst possible outcome for a file
#     about to be uploaded.
#
# Theme artwork is never in the archive by construction: it is fetched at apply
# time and verified against a pinned SHA256 (see scripts/lib/moe.sh).
#
#   make dist
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
	@bash $(REPO)/run.sh --list

## list-utilities: list standalone utilities
list-utilities:
	@bash $(REPO)/run.sh --list-utilities

## clean: remove test scratch dirs (never touches $HOME or the repo)
clean:
	@rm -rf /tmp/devmkde-* /tmp/devmkde-aptchecks.* 2>/dev/null || true
	@echo "cleaned test scratch dirs"