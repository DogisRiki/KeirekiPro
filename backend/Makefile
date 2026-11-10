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

# 道具の設定のファイル。道具が、承認の対象のファイルと別の名前の設定のファイルを読まないように、名前で指定する
GOLANGCI_CONFIG := .golangci.yml
COVERAGE_CONFIG := .testcoverage.yml
GREMLINS_CONFIG := .gremlins.yaml

MODULE := github.com/DogisRiki/KeirekiPro/backend
COVERAGE_PROFILE := coverage.out
COVERAGE_INTERNAL_PROFILE := coverage.internal.out

# 全体の変異テストの JSON の報告。週次の報告がこのファイルを読む
MUTATION_REPORT ?= mutation-report.json

# 比べる検査は、Java 版と Go 版のイメージを組み立ててから比べるので、go test の既定の10分では足りない
COMPAT_TIMEOUT ?= 60m

.PHONY: generate generate-check fmt fmt-check lint test coverage build check \
	mutation-diff mutation-full vuln compat compat-cross compat-perf

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

## fmt: 書式を直す
fmt:
	golangci-lint fmt --config=$(GOLANGCI_CONFIG)

## fmt-check: 書式の違いを見つけたら止める
fmt-check:
	golangci-lint fmt --config=$(GOLANGCI_CONFIG) --diff

## lint: 静的な検査と、depguard による依存の向きの検査
lint:
	golangci-lint run --config=$(GOLANGCI_CONFIG)

## test: 単体テストと結合テスト。結合テストは testcontainers-go で Postgres と Redis を動かす
test:
	go test -race -coverprofile=$(COVERAGE_PROFILE) ./...

## coverage: ./internal/... の文の割合が下限に届くかを確かめる(make test のあとに動かす)
# coverage.out の1行目(計り方の行)と、internal/ の下のファイルの行だけを写す。
# grep は、当たる行が無いときに 1 で終わるので、1 のときだけ失敗にしない
coverage:
	{ head -n 1 $(COVERAGE_PROFILE); grep '^$(MODULE)/internal/' $(COVERAGE_PROFILE) || [ $$? -eq 1 ]; } > $(COVERAGE_INTERNAL_PROFILE)
	go tool go-test-coverage --config=$(COVERAGE_CONFIG)

## build: 組み立てられるかを確かめる。比べる検査のコードは、backend/compat/ があるときだけ組み立てる
build:
	go build ./...
	if [ -d compat ]; then go build -tags compat ./compat/...; fi

## check: 品質チェックの全部
check:
	$(MAKE) fmt-check
	$(MAKE) generate-check
	$(MAKE) lint
	$(MAKE) test
	$(MAKE) coverage
	$(MAKE) build

## mutation-diff: BASE(git の参照)から変えた箇所の変異テスト。git の履歴が要るので CI でだけ動かす
mutation-diff:
	$(if $(BASE),,$(error BASE に比べる元の git の参照を指定してください。例: make mutation-diff BASE=origin/main))
	go tool gremlins unleash --config=$(GREMLINS_CONFIG) --diff "$(BASE)" --threshold-efficacy 80 --threshold-mcover 93

## mutation-full: 全体の変異テスト。JSON の報告を MUTATION_REPORT に書く
mutation-full:
	go tool gremlins unleash --config=$(GREMLINS_CONFIG) --output=$(MUTATION_REPORT)

## vuln: 呼ばれる箇所のある脆弱性の検査
vuln:
	go tool govulncheck ./...

# 比べる検査の3つの入口は、テストの関数の名前で分ける。
# compat_test.go の比べる検査は TestCross_ と TestPerf_ で始まらない名前、
# cross_test.go の版をまたぐ確認は TestCross_ で始まる名前、perf_test.go の応答の時間の比べ方は TestPerf_ で始まる名前にする

## compat: Java 版と Go 版の応答を比べる検査
compat:
	go test -tags compat -count=1 -timeout $(COMPAT_TIMEOUT) -skip '^Test(Cross|Perf)_' ./compat/...

## compat-cross: 片方の版が保存した内容をもう一方の版が読めるかの確認
compat-cross:
	go test -tags compat -count=1 -timeout $(COMPAT_TIMEOUT) -run '^TestCross_' ./compat/...

## compat-perf: Java 版と Go 版の応答の時間の比べ方。PR の検査では動かさない
compat-perf:
	go test -tags compat -count=1 -timeout $(COMPAT_TIMEOUT) -run '^TestPerf_' ./compat/...
