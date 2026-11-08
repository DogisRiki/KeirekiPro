# Go 版の backend の作業の入口。
# 手元では、コンテナの中で動かす(例: bash .claude/scripts/parallel/run-check.sh backend-go make generate)。
# CI では backend/ でそのまま動かす。
SHELL := /bin/bash
.SHELLFLAGS := -euo pipefail -c

# 仕様書から生成する受け口のコード
OAPI_CONFIG := api/oapi-codegen.yaml
OAPI_SPEC := api/openapi.yaml
OAPI_OUT_DIR := internal/httpapi/gen

# SQL から生成する問い合わせのコード。
# sqlc は、問い合わせのファイルが1つも無いと失敗するため、問い合わせのファイルがあるときだけ動かす
SQLC_CONFIG := sqlc.yaml
SQLC_QUERIES := $(wildcard db/queries/*.sql)
SQLC_SCHEMA := $(wildcard src/main/resources/db/migration/*.sql)
SQLC_OUT_DIR := internal/platform/database/sqlcgen

.PHONY: generate generate-check

## generate: 仕様書と SQL からコードを生成する
generate:
	mkdir -p $(OAPI_OUT_DIR)
	go tool oapi-codegen -config $(OAPI_CONFIG) -o $(OAPI_OUT_DIR)/api.gen.go $(OAPI_SPEC)
ifneq ($(SQLC_QUERIES),)
	go tool sqlc generate -f $(SQLC_CONFIG)
endif

## generate-check: 生成したコードが、仕様書と SQL から今生成したものと同じかを確かめる
# 一時のフォルダに生成して diff -r で比べる。git を使わないのは、作業のフォルダが git の worktree のとき、
# コンテナの中で git の履歴を読めないためである
generate-check:
	tmp="$$(mktemp -d)"; \
	trap 'rm -rf "$$tmp"' EXIT; \
	ok=1; \
	mkdir -p "$$tmp/$(OAPI_OUT_DIR)"; \
	go tool oapi-codegen -config $(OAPI_CONFIG) -o "$$tmp/$(OAPI_OUT_DIR)/api.gen.go" $(OAPI_SPEC); \
	if ! diff -r $(OAPI_OUT_DIR) "$$tmp/$(OAPI_OUT_DIR)"; then \
		echo "$(OAPI_OUT_DIR) が、$(OAPI_SPEC) から生成したコードと食い違っています。make generate を動かしてください" >&2; \
		ok=0; \
	fi; \
	if [ -n "$(SQLC_QUERIES)" ]; then \
		cp --parents $(SQLC_CONFIG) $(SQLC_SCHEMA) $(SQLC_QUERIES) "$$tmp/"; \
		go tool sqlc generate -f "$$tmp/$(SQLC_CONFIG)"; \
		if ! diff -r $(SQLC_OUT_DIR) "$$tmp/$(SQLC_OUT_DIR)"; then \
			echo "$(SQLC_OUT_DIR) が、db/queries の SQL から生成したコードと食い違っています。make generate を動かしてください" >&2; \
			ok=0; \
		fi; \
	elif [ -e $(SQLC_OUT_DIR) ]; then \
		echo "db/queries に SQL が無いのに、$(SQLC_OUT_DIR) が残っています。消してください" >&2; \
		ok=0; \
	fi; \
	if [ "$$ok" -ne 1 ]; then exit 1; fi; \
	echo "生成したコードは、仕様書と SQL から今生成したものと同じです"
