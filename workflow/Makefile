.PHONY: build lock

# Authoritative Bun image digest version 1.3.5
BUN_IMAGE = oven/bun@sha256:f48ca3e042de3c9da0afb25455414db376c873bf88f79ffb6f26aec82bdb6da2

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
	$(if $(wildcard package.json),,$(error package.json not found in workflow/. This file is required for the build))
	$(if $(wildcard bun.lock),,$(error bun.lock not found in workflow/. Run 'make lock' to generate it or ask the workflow author to include their lockfile))
	$(if $(wildcard Dockerfile),,$(error Dockerfile not found in workflow/. Restore it from the template))
	$(if $(wildcard main.ts),,$(error main.ts not found in workflow/. The workflow entry point is missing))
	docker build --platform=linux/amd64 --output type=local,dest="$(CURDIR)" .
	@echo "Build complete. workflow.wasm is ready in $(CURDIR)/wasm"
endif

lock:
	docker build --platform=linux/amd64 -f Dockerfile.lock --output type=local,dest="$(CURDIR)" .
