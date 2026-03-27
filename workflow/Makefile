.PHONY: build lock

build:
ifeq ($(CRE_DOCKER_BUILD_IMAGE),true)
	@if [ ! -f bun.lock ]; then \
		echo "ERROR: bun.lock is missing."; \
		echo "To ensure a reproducible toolchain, please run 'make lock' from:"; \
		echo "  $(CURDIR)"; \
		echo "If you are expecting to verify this workflow, it's possible verification will fail if the generated lock differs, instead ask the original author to publish their lock file."; \
		exit 1; \
	fi
	mkdir -p wasm
	bun cre-compile main.ts wasm/workflow.wasm
else
	$(if $(wildcard package.json),,$(error ERROR: package.json not found in workflow/. This file is required for the build))
	$(if $(wildcard bun.lock),,$(error ERROR: bun.lock is missing. To ensure a reproducible toolchain, run 'make lock' from $(CURDIR). If you are expecting to verify this workflow, it is possible verification will fail if the generated lock differs, instead ask the original author to publish their lock file))
	$(if $(wildcard Dockerfile),,$(error ERROR: Dockerfile not found in workflow/. Restore it from the template))
	$(if $(wildcard main.ts),,$(error ERROR: main.ts not found in workflow/. The workflow entry point is missing))
	docker build --platform=linux/amd64 --output type=local,dest="$(CURDIR)" .
	@echo "Build complete. workflow.wasm is ready in $(CURDIR)/wasm"
endif

lock:
	docker build --platform=linux/amd64 -f Dockerfile.lock --output type=local,dest="$(CURDIR)" .
