# CALYX FSM Bundle (Lua Edition) -- Survival Lab
#
# Every require is root-relative and bundler.lua hardcodes root_dir = "core",
# so every target runs from the repo root. See README.md "Running Things".
#
# Usage:
#   make help         list targets
#   make verify       single sanity gate: bundle -> test-all -> lint -> format-check -> sync-check
#   make test-all     run all 11 test files from root (no aggregate runner exists)

LUA ?= lua
LUACHECK ?= luacheck
DOCKER_COMPOSE ?= docker-compose
STYLUA_IMAGE ?= johnnymorganz/stylua:2.6.0
PORT ?= 8080
REDIS_HOST ?= 127.0.0.1
REDIS_PORT ?= 6379

BUNDLE = calyx_bundle.lua
CORE_DIR = core

TESTS = test_hardened.lua \
	breakage_suite/test_context_loss.lua \
	breakage_suite/test_example_professional.lua \
	breakage_suite/test_unregistered_event.lua \
	breakage_suite/test_invalid_fsm_schema.lua \
	breakage_suite/test_export_fsm.lua \
	breakage_suite/test_log_host.lua \
	breakage_suite/test_prometheus_host.lua \
	breakage_suite/test_mailbox_debug.lua \
	breakage_suite/test_mailbox_overflow.lua \
	breakage_suite/test_reporting_demo.lua

.PHONY: all bundle demo redis-demo sqlite-demo nginx-demo test test-all \
	test-context-loss test-overflow lint format-check \
	docker-up smoke smoke-local docker-down \
	sync sync-check verify clean help

all: bundle

# calyx_bundle.lua is GENERATED: it embeds core/*.lua verbatim, but the file
# header carries a generation timestamp, so two regenerations are never
# byte-identical. Regenerate, then re-verify. Never lint or format the bundle
# directly -- fix core/ instead (see .luacheckrc, .styluaignore).
bundle:
	@echo ">> Regenerating $(BUNDLE) from $(CORE_DIR)/"
	$(LUA) bundler.lua

# Library use example from README
demo: bundle
	$(LUA) demo.lua

redis-demo: bundle
	@echo ">> WARNING: FLUSHES Redis at $(REDIS_HOST):$(REDIS_PORT)"
	CALYX_REDIS_HOST=$(REDIS_HOST) CALYX_REDIS_PORT=$(REDIS_PORT) $(LUA) run_redis_demo.lua

sqlite-demo: bundle
	$(LUA) run_demo.lua

nginx-demo: bundle
	@echo ">> Needs OpenResty on :$(PORT) - see openresty/nginx.conf"
	$(LUA) run_nginx_demo.lua

# 11 files, no aggregate runner - this IS the aggregate. Run from root.
test-all: bundle
	@for t in $(TESTS); do \
		echo ">> $$t"; \
		$(LUA) $$t || exit 1; \
	done

test: bundle
	$(LUA) test_hardened.lua

# Individual breakage targets (examples; full list via test-all)
test-context-loss: bundle
	$(LUA) breakage_suite/test_context_loss.lua

test-overflow: bundle
	$(LUA) breakage_suite/test_mailbox_overflow.lua

# Lint is informational: 74 warnings is the post-tightening baseline, 0 errors.
# See BASELINE_LINT.md for classification and .luacheckrc for justifications.
lint:
	$(LUACHECK) .

# Format CHECK only -- changes no sources (CONTRIBUTING.md phase rule).
# Config comes from ./stylua.toml; ./calyx_bundle.lua is excluded via
# ./.styluaignore (generated AND unparseable). The image has no shell, so
# --entrypoint /stylua is required. Expect 10 files listed (BASELINE_LINT.md).
format-check:
	docker run --rm --entrypoint /stylua -v "$(PWD):/work" -w /work $(STYLUA_IMAGE) --check --output-format=summary .

# Container stack -- verified end to end, see README. Host port overridable:
# CALYX_PORT=8081 make docker-up (or PORT=8081, mapped to CALYX_PORT below).
docker-up:
	CALYX_PORT=$(PORT) $(DOCKER_COMPOSE) up -d --build

# Runs the 13 checks inside the compose network (BASE=http://openresty:8080).
smoke:
	CALYX_PORT=$(PORT) $(DOCKER_COMPOSE) run --rm smoke

# Same 13 checks against a local/bare-metal instance on :$(PORT).
smoke-local:
	BASE=http://127.0.0.1:$(PORT) sh openresty/smoke.sh

docker-down:
	$(DOCKER_COMPOSE) down -v

# Bare-metal install + drift check. The container mounts the repo read-only so
# it needs neither; bare-metal creates a second copy that can rot -- re-run
# sync after every change. See tools/sync_lualib.sh header.
sync:
	tools/sync_lualib.sh

sync-check:
	tools/sync_lualib.sh --check

# Single "is this repo sane?" gate.
# NOTE: sync-check compares the repo against the installed lualib copy
# (default /usr/local/openresty/site/lualib). On a box with no bare-metal
# install it reports DRIFT (exit 1) -- correct behavior, not a Makefile bug.
verify: bundle test-all lint format-check sync-check

clean:
	rm -f session_demo.db
	rm -f *.db
	rm -rf survival_reports/*.json

help:
	@echo "CALYX Survival Lab -- make targets (all run from repo root)"
	@echo ""
	@echo "  bundle          regenerate $(BUNDLE) from $(CORE_DIR)/"
	@echo "  demo            lua demo.lua"
	@echo "  redis-demo      lua run_redis_demo.lua (FLUSHES Redis at $(REDIS_HOST):$(REDIS_PORT))"
	@echo "  sqlite-demo     lua run_demo.lua"
	@echo "  nginx-demo      lua run_nginx_demo.lua (needs OpenResty on :$(PORT))"
	@echo "  test            lua test_hardened.lua"
	@echo "  test-all        run all 11 test files from root"
	@echo "  test-context-loss  single breakage example"
	@echo "  test-overflow   single breakage example"
	@echo "  lint            luacheck . (74-warning baseline, 0 errors)"
	@echo "  format-check    StyLua --check via $(STYLUA_IMAGE) (check only, changes nothing)"
	@echo "  docker-up       CALYX_PORT=$(PORT) docker-compose up -d --build"
	@echo "  smoke           compose smoke service (13 checks, inside network)"
	@echo "  smoke-local     same 13 checks vs http://127.0.0.1:$(PORT)"
	@echo "  docker-down     docker-compose down -v"
	@echo "  sync            install lualib files for bare-metal OpenResty"
	@echo "  sync-check      report installed-copy drift (non-zero = drifted)"
	@echo "  verify          bundle -> test-all -> lint -> format-check -> sync-check"
	@echo "  clean           remove session_demo.db, *.db, survival_reports/*.json"
