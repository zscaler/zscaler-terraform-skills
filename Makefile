COLOR_OK=\x1b[0;32m
COLOR_NONE=\x1b[0m
COLOR_ERROR=\x1b[31;01m
COLOR_WARNING=\x1b[33;01m
COLOR_ZSCALER=\x1B[34;01m

PYTHON  ?= python3
SKILLS  := $(wildcard skills/*/SKILL.md)

.PHONY: help validate check check-versions \
        check-frontmatter check-links check-line-counts \
        line-counts fmt lint lint-fix \
        spec-check release-dry clean

help:
	@printf "$(COLOR_ZSCALER)"
	@echo "  ______              _           "
	@echo " |___  /             | |          "
	@echo "    / / ___  ___ __ _| | ___ _ __ "
	@echo "   / / / __|/ __/ _\` | |/ _ \ '__|"
	@echo "  / /__\__ \ (_| (_| | |  __/ |   "
	@echo " /_____|___/\___\__,_|_|\___|_|   "
	@echo "                                  "
	@printf "$(COLOR_NONE)\n"
	@printf "$(COLOR_OK)Zscaler Terraform Skills$(COLOR_NONE) — local validation toolkit\n"
	@echo ""
	@printf "$(COLOR_WARNING)Usage:$(COLOR_NONE) make [target]\n"
	@echo ""
	@printf "$(COLOR_WARNING)Validation$(COLOR_NONE)\n"
	@printf "$(COLOR_OK)  validate$(COLOR_NONE)            Run every check below (mirror of CI)\n"
	@printf "$(COLOR_OK)  check-frontmatter$(COLOR_NONE)   Validate YAML frontmatter in every SKILL.md\n"
	@printf "$(COLOR_OK)  check-links$(COLOR_NONE)         Verify all internal references/*.md links resolve\n"
	@printf "$(COLOR_OK)  check-line-counts$(COLOR_NONE)   Warn if any SKILL.md exceeds 300 lines (token budget)\n"
	@printf "$(COLOR_OK)  check-versions$(COLOR_NONE)      Verify marketplace.json + gemini-extension.json + every SKILL.md agree on version\n"
	@printf "$(COLOR_OK)  spec-check$(COLOR_NONE)          Validate every skill against the agentskills.io spec via 'gh skill publish --dry-run'\n"
	@printf "$(COLOR_OK)  line-counts$(COLOR_NONE)         Show line counts for every SKILL.md and reference file\n"
	@echo ""
	@printf "$(COLOR_WARNING)Release$(COLOR_NONE)  (production releases run automatically on merge to master)\n"
	@printf "$(COLOR_OK)  release-dry$(COLOR_NONE)         Preview what semantic-release would publish from local commits (no writes)\n"
	@echo ""
	@printf "$(COLOR_WARNING)Formatting$(COLOR_NONE)\n"
	@printf "$(COLOR_OK)  fmt$(COLOR_NONE)                 Format markdown with prettier (if installed)\n"
	@printf "$(COLOR_OK)  lint$(COLOR_NONE)                Lint markdown with markdownlint-cli (uses .markdownlint.json)\n"
	@printf "$(COLOR_OK)  lint-fix$(COLOR_NONE)            Auto-fix every lint issue markdownlint can fix\n"
	@echo ""
	@printf "$(COLOR_WARNING)Housekeeping$(COLOR_NONE)\n"
	@printf "$(COLOR_OK)  clean$(COLOR_NONE)               Remove __pycache__, .DS_Store, transient artifacts\n"

# -------- aggregate --------

validate: check-frontmatter check-links check-line-counts check-versions lint
	@printf "$(COLOR_OK)All validation checks passed.$(COLOR_NONE)\n"

check: validate

# -------- versioning (read-only — writes happen via semantic-release in CI) --------

check-versions:
	@$(PYTHON) scripts/release/sync_versions.py --check

# -------- frontmatter --------

check-frontmatter:
	@$(PYTHON) scripts/check_frontmatter.py

# -------- internal markdown links --------

check-links:
	@$(PYTHON) scripts/check_links.py

# -------- line counts --------

line-counts:
	@printf "$(COLOR_WARNING)SKILL.md files (target: < 300 lines):$(COLOR_NONE)\n"
	@wc -l $(SKILLS) | sed 's/^/  /'
	@echo ""
	@printf "$(COLOR_WARNING)Reference files (target: < 400 lines per subsection):$(COLOR_NONE)\n"
	@wc -l skills/*/references/*.md 2>/dev/null | sed 's/^/  /'

check-line-counts:
	@failed=0; \
	for f in $(SKILLS); do \
	  n=$$(wc -l < "$$f"); \
	  if [ "$$n" -gt 300 ]; then \
	    printf "$(COLOR_ERROR)OVER  $$f: $$n lines (>300)$(COLOR_NONE)\n"; \
	    failed=1; \
	  else \
	    printf "  ok  $$f: $$n lines\n"; \
	  fi; \
	done; \
	exit $$failed

# -------- agentskills.io spec compliance --------

# Validates every skills/*/SKILL.md against the agentskills.io spec without publishing.
# Requires gh >= 2.90.0 (the version that introduced `gh skill`). Never runs the
# publish phase — releases come exclusively from semantic-release on merge to master.
spec-check:
	@if ! command -v gh >/dev/null 2>&1; then \
	  printf "$(COLOR_WARNING)gh CLI not installed.$(COLOR_NONE) Install: brew install gh (need >= 2.90.0)\n"; \
	  exit 1; \
	fi
	@printf "$(COLOR_WARNING)gh skill spec validation (dry-run, no publish):$(COLOR_NONE)\n"
	@gh skill publish --dry-run

# -------- release preview --------

# Pulls semantic-release + plugins on demand via npx (no package.json checked in).
release-dry:
	@printf "$(COLOR_WARNING)semantic-release dry-run (no writes, no tags, no GitHub release):$(COLOR_NONE)\n"
	@npx --yes \
	  -p semantic-release@24 \
	  -p @semantic-release/changelog@6 \
	  -p @semantic-release/exec@6 \
	  -p @semantic-release/git@10 \
	  -p conventional-changelog-conventionalcommits@8 \
	  semantic-release --dry-run --no-ci

# -------- formatting --------

fmt:
	@if command -v prettier >/dev/null 2>&1; then \
	  prettier --write "skills/**/*.md" "*.md"; \
	else \
	  printf "$(COLOR_WARNING)prettier not installed.$(COLOR_NONE) Install: npm install -g prettier\n"; \
	fi

lint:
	@if command -v markdownlint >/dev/null 2>&1; then \
	  markdownlint --config .markdownlint.json --ignore-path .markdownlintignore "**/*.md"; \
	else \
	  printf "$(COLOR_WARNING)markdownlint not installed.$(COLOR_NONE) Install: npm install -g markdownlint-cli\n"; \
	  exit 1; \
	fi

lint-fix:
	@if command -v markdownlint >/dev/null 2>&1; then \
	  markdownlint --fix --config .markdownlint.json --ignore-path .markdownlintignore "**/*.md"; \
	  printf "$(COLOR_OK)Auto-fixable lint issues resolved.$(COLOR_NONE) Re-run 'make lint' to see anything that needs manual attention.\n"; \
	else \
	  printf "$(COLOR_WARNING)markdownlint not installed.$(COLOR_NONE) Install: npm install -g markdownlint-cli\n"; \
	  exit 1; \
	fi

# -------- housekeeping --------

clean:
	@find . -type d -name "__pycache__" -prune -exec rm -rf {} +
	@find . -type f -name ".DS_Store" -delete
	@printf "$(COLOR_OK)Cleaned __pycache__ and .DS_Store.$(COLOR_NONE)\n"
