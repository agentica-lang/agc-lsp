AGENTICA ?= agentica

.PHONY: check test

check:
	$(AGENTICA) check src/main.agc
	$(AGENTICA) check specs/steps.agc

test: check
	$(AGENTICA) test specs --steps specs/steps.agc
