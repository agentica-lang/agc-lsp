AGENTICA ?= agentica
AGENTICA_VERSION := $(shell sed -n 's/^  AGENTICA_VERSION: "\(.*\)"$$/\1/p' .github/workflows/ci.yml)
WINE = docker compose run --rm wine

export AGENTICA_VERSION

.PHONY: check smoke test wine wine-check wine-smoke

check:
	$(AGENTICA) check src/main.agc
	$(AGENTICA) check bin/prepare.agc
	$(AGENTICA) check specs/smoke.agc
	$(AGENTICA) check specs/steps.agc

smoke:
	dir=$$(mktemp -d) && trap 'rm -rf "$$dir"' EXIT && \
	  $(AGENTICA) specs/smoke.agc input "$$dir/in" && \
	  AGENTICA="$(AGENTICA)" AGC_LSP_CACHE="$$dir/cache" bin/agc-lsp --stdio < "$$dir/in" > "$$dir/out" && \
	  $(AGENTICA) specs/smoke.agc verify "$$dir/out"

test: check smoke
	$(AGENTICA) test specs --steps specs/steps.agc

wine: wine-check wine-smoke

wine-check:
	$(WINE) sh -c 'for file in src/main.agc bin/prepare.agc specs/smoke.agc specs/steps.agc; do agentica check $$file || exit 1; done'

wine-smoke:
	$(WINE) sh docker/wine/smoke.sh
