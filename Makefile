.PHONY: build

build:
ifeq ($(CRE_DOCKER_BUILD_IMAGE),true)
	# --- RUNNING INSIDE DOCKER ---
	mkdir -p wasm
	bun cre-compile main.ts wasm/workflow.wasm

else
	# --- RUNNING ON THE HOST ---
	# We enforce the platform and use --output to pull the contents 
	# of the 'scratch' stage directly into the current directory.
	docker build --platform=linux/amd64 --output type=local,dest=. .
	
	@echo "Build complete. workflow.wasm is ready on the host."
endif
