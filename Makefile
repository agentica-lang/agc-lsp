AGENTICA ?= agentica

.PHONY: check smoke test

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
