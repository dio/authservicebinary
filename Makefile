# Copyright 2022 Dhi Aurrahman
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Include versions of tools we build or fetch on-demand.
include Tools.mk

# Root dir returns absolute path of current directory. It has a trailing "/".
root_dir := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))

# Currently we resolve it using which. But more sophisticated approach is to use infer GOROOT.
go     := $(shell which go)
goarch := $(shell $(go) env GOARCH)
goexe  := $(shell $(go) env GOEXE)
goos   := $(shell $(go) env GOOS)

# Local cache directory.
CACHE_DIR ?= $(root_dir).cache

# Go tools directory holds the binaries of Go-based tools.
go_tools_dir := $(CACHE_DIR)/tools/go
# Prepackaged tools may have more than precompiled binaries, e.g. for protoc, it also has an include
# directory which contains well-known proto files: https://github.com/protocolbuffers/protobuf/tree/master/src/google/protobuf.
prepackaged_tools_dir := $(CACHE_DIR)/tools/prepackaged

# By default, a protoc-gen-<name> program is expected to be on your PATH so that it can be
# discovered and executed by buf. This makes sure the Go-based and prepackaged tools dirs are
# registered in the PATH for buf to pick up. As an alternative, we can specify "path"
# https://docs.buf.build/configuration/v1/buf-gen-yaml#path for each plugin entry in buf.gen.yaml,
# however that means we need to override buf.gen.yaml at runtime. Note: since remote plugin
# execution https://docs.buf.build/bsr/remote-generation/remote-plugin-execution is available, one
# should check that out first before downloading local protoc plugins.
export PATH := $(go_tools_dir):$(prepackaged_tools_dir)/bin:$(PATH)

# Pre-packaged targets.
clang-format := $(prepackaged_tools_dir)/bin/clang-format

# Go-based tools.
addlicense          := $(go_tools_dir)/addlicense
buf                 := $(go_tools_dir)/buf
protoc-gen-validate := $(go_tools_dir)/protoc-gen-validate
golangci-lint       := $(go_tools_dir)/golangci-lint
goimports           := $(go_tools_dir)/goimports

# Assorted tools required for processing proto files.
proto_tools := \
	$(buf) \
	$(protoc-gen-validate)

# We cache the deps fetched by buf locally (in-situ) by setting BUF_CACHE_DIR
# https://docs.buf.build/bsr/overview#module-cache, so it can be referenced by other tools.
export BUF_CACHE_DIR := $(root_dir).cache/buf
BUF_V1_MODULE_DATA   := $(BUF_CACHE_DIR)/v1/module/data/buf.build

# By default, unless GOMAXPROCS is set via an environment variable or explicity in the code, the
# tests are run with GOMAXPROCS=1. This is problematic if the tests require more than one CPU, for
# example when running t.Parallel() in tests.
export GOMAXPROCS ?=4
test: ## Run all unit tests
	@$(go) test ./internal/...

gen: $(BUF_V1_MODULE_DATA)
	@$(buf) generate

update: # Update authservice to latest commit
	@git submodule update --remote --merge

check: # Make sure we follow the rules
	@rm -fr generated
	@$(MAKE) gen format lint license
	@if [ ! -z "`git status -s`" ]; then \
		echo "The following differences will fail CI until committed:"; \
		git diff --exit-code; \
	fi

license_ignore :=
license_files  := api example internal buf.*.yaml
license: $(addlicense)
	@$(addlicense) $(license_ignore) -c "Dhi Aurrahman"  $(license_files) 1>/dev/null 2>&1

all_nongen_go_sources := $(wildcard api/*.go example/*.go internal/*.go internal/*/*.go internal/*/*/*.go)
format: go.mod $(all_nongen_go_sources) $(goimports)
	@$(go) mod tidy
	@$(go)fmt -s -w $(all_nongen_go_sources)
# Workaround inconsistent goimports grouping with awk until golang/go#20818 or incu6us/goimports-reviser#50
	@for f in $(all_nongen_go_sources); do \
			awk '/^import \($$/,/^\)$$/{if($$0=="")next}{print}' $$f > /tmp/fmt; \
	    mv /tmp/fmt $$f; \
	done
	@$(goimports) -local $$(sed -ne 's/^module //gp' go.mod) -w $(all_nongen_go_sources)

# Override lint cache directory. https://golangci-lint.run/usage/configuration/#cache.
export GOLANGCI_LINT_CACHE=$(CACHE_DIR)/golangci-lint
lint: .golangci.yml $(all_nongen_go_sources) $(golangci-lint)
	@printf "$(ansi_format_dark)" $@ "linting Go files..."
	@$(golangci-lint) run --timeout 5m --config $< ./...
	@printf "$(ansi_format_bright)" $@ "ok"

authservice_dir := $(root_dir)authservice
# BUF_V1_MODULE_DATA can only be generated by buf generate or build.
# Note that since we use newer buf binary, the buf.lock contains "version: v1" entry which is not
# backward compatible with older version of buf.
$(BUF_V1_MODULE_DATA): $(authservice_dir)/buf.yaml $(authservice_dir)/buf.lock $(proto_tools)
	@$(buf) lint
	@$(buf) build

$(authservice_dir)/buf.yaml:
	@git submodule update --init

# Catch all rules for Go-based tools.
$(go_tools_dir)/%:
	@GOBIN=$(go_tools_dir) go install $($(notdir $@)@v)

# Install clang-format from https://github.com/angular/clang-format. We don't support win32 yet as
# this script will fail.
clang-format-download-archive-url = https://$(subst @,/archive/refs/tags/,$($(notdir $1)@v)).tar.gz
clang-format-dir                  = $(subst github.com/angular/clang-format@v,clang-format-,$($(notdir $1)@v))
$(clang-format):
	@printf "$(ansi_format_dark)" tools "installing $($(notdir $@)@v)..."
	@mkdir -p $(dir $@)
	@curl -sSL $(call clang-format-download-archive-url,$@) | tar xzf - -C $(prepackaged_tools_dir)/bin \
		--strip 3 $(call clang-format-dir,$@)/bin/$(goos)_x64
	@printf "$(ansi_format_bright)" tools "ok"
