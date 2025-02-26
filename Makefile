SHELL := /bin/sh

# 目錄常數定義
BUILD_DIR := "$(shell pwd)/Build"
RELEASE_DIR := "$(BUILD_DIR)/Release"
INTERMEDIATE_DIR := "$(BUILD_DIR)/Intermediate"
CHEWING_C_INITIALIZER := "$(shell pwd)/bin/libchewing-database-initializer/init_database"
CONFIG_DIR_LINUX := "$(HOME)/.config/chewing"
CONFIG_DIR_WIN := "C:/Users/$(USERNAME)/ChewingTextService"

.PHONY: BuildDir format lint clean install macv macv-json install-vchewing \
        fcitx5-chs fcitx5-cht fcitx5-install \
        libchewing-all libchewing-chs libchewing-cht libchewing-rust \
        libchewing-c-prepare-macos libchewing-c-prepare-linux-amd64 \
        libchewing-all-c libv-c-chs libv-c-cht libchewing-c \
        _remoteinstall-vchewing gc gitcfg

# MARK: - General

BuildDir:
	@mkdir -p ./Build

format:
	@swiftformat --swiftversion 5.5 --indent 2 ./

lint:
	@git ls-files --exclude-standard | grep -E '\.swift$$' | swiftlint --fix --autocorrect

clean:
	@rm -rf ./Build
	@rm -rf ./.build

# MARK: - macOS (vChewing)

install: install-vchewing clean

macv: BuildDir
	@mkdir -p ./Build/Release/
	@swift ./bin/cook_mac.swift
	@sqlite3 ./Build/Release/vChewingFactoryDatabase.sqlite < ./Build/Release/vChewingFactoryDatabase.sql

macv-json: BuildDir
	@mkdir -p ./Build/Release/
	@swift ./bin/cook_mac.swift --json

install-vchewing: macv
	@echo "\033[0;32m//$$(tput bold) macOS: 正在部署威注音核心語彙檔案……$$(tput sgr0)\033[0m"
	@mkdir -p "$(HOME)/Library/Containers/org.atelierInmu.inputmethod.vChewing/Data/Library/Application Support/vChewingFactoryData/"
	@cp -a ./Build/Release/vChewingFactoryDatabase.sqlite "$(HOME)/Library/Containers/org.atelierInmu.inputmethod.vChewing/Data/Library/Application Support/vChewingFactoryData/"

	@pkill -HUP -f vChewing || echo "// vChewing is not running"
	@echo "\033[0;32m//$$(tput bold) macOS: 核心語彙檔案部署成功。$$(tput sgr0)\033[0m"

# MARK: - Linux (McBopomofo)

fcitx5-chs: macv-json
	@echo "\033[0;32m//$$(tput bold) Linux: 正在生成 FCITX5 版小麥注音專用的簡體中文威注音語料檔案……$$(tput sgr0)\033[0m"
	@> ./mcbopomofo-data.txt
	@echo "# format org.openvanilla.mcbopomofo.sorted" >> ./mcbopomofo-data.txt
	@env LC_COLLATE=C.UTF-8 cat ./data-chs.txt >> ./mcbopomofo-data.txt
	
fcitx5-cht: macv-json
	@echo "\033[0;32m//$$(tput bold) Linux: 正在生成 FCITX5 版小麥注音專用的繁體中文威注音語料檔案……$$(tput sgr0)\033[0m"
	@> ./mcbopomofo-data.txt
	@echo "# format org.openvanilla.mcbopomofo.sorted" >> ./mcbopomofo-data.txt
	@env LC_COLLATE=C.UTF-8 cat ./data-cht.txt >> ./mcbopomofo-data.txt

fcitx5-install:
	@cp ./mcbopomofo-data.txt /usr/share/fcitx5/data/

# MARK: - LibChewing (Rust-Based)

libchewing-all: libchewing-chs libchewing-cht

libchewing-chs:
	$(MAKE) libchewing-rust LANG=chs

libchewing-cht:
	$(MAKE) libchewing-rust LANG=cht

libchewing-rust:
	@$(eval LANG := $(LANG))
	@$(eval WORK_DIR := "$(INTERMEDIATE_DIR)/LibChewing-$(shell echo $(LANG) | tr 'a-z' 'A-Z')")
	@$(eval BUILD_DIR_RUST := "$(RELEASE_DIR)/LibChewing-$(shell echo $(LANG) | tr 'a-z' 'A-Z')/Rust_Based")
	@mkdir -p "$(BUILD_DIR_RUST)/"
	@mkdir -p "$(WORK_DIR)/"
	@swift ./bin/cook_libchewing.swift $(LANG)
	@chewing-cli init-database -t trie "$(WORK_DIR)/tsi.src" "$(WORK_DIR)/tsi.dat"
	@chewing-cli init-database -t trie "$(WORK_DIR)/word.src" "$(WORK_DIR)/word.dat"
	@mv "$(WORK_DIR)/tsi.dat" "$(WORK_DIR)/word.dat" "$(BUILD_DIR_RUST)/"

libchewing-install: libchewing-rust
	@$(eval LANG := $(shell echo $(LANG) | tr 'A-Z' 'a-z'))
	@$(eval BUILD_DIR_RUST := "$(RELEASE_DIR)/LibChewing-$(shell echo $(LANG) | tr 'a-z' 'A-Z')/Rust_Based")
	@if [ "$(OS)" = "Windows_NT" ]; then \
		mkdir -p $(CONFIG_DIR_WIN); \
		cp "$(BUILD_DIR_RUST)/tsi.dat" "$(BUILD_DIR_RUST)/word.dat" $(CONFIG_DIR_WIN)/; \
		echo "\033[0;32m//$$(tput bold) 已將詞庫檔案部署至 $(CONFIG_DIR_WIN) 目錄下。$$(tput sgr0)\033[0m"; \
	else \
		mkdir -p $(CONFIG_DIR_LINUX); \
		cp "$(BUILD_DIR_RUST)/tsi.dat" "$(BUILD_DIR_RUST)/word.dat" $(CONFIG_DIR_LINUX)/; \
		echo "\033[0;32m//$$(tput bold) 已將詞庫檔案部署至 $(CONFIG_DIR_LINUX) 目錄下。$$(tput sgr0)\033[0m"; \
	fi

# MARK: - LibChewing (C-Based)

libchewing-c-prepare-macos:
	@echo "\033[0;32m//$$(tput bold) 已經準備設定 macOS 專用酷音編譯器……$$(tput sgr0)\033[0m"
	@cp ./bin/libchewing-database-initializer/init_database_macos_universal ./bin/libchewing-database-initializer/init_database

libchewing-c-prepare-linux-amd64:
	@echo "\033[0;32m//$$(tput bold) 已經準備設定 Linux amd64 專用酷音編譯器……$$(tput sgr0)\033[0m"
	@cp ./bin/libchewing-database-initializer/init_database_linux_amd64 ./bin/libchewing-database-initializer/init_database

libchewing-all-c: libv-c-chs libv-c-cht

libv-c-chs:
	$(MAKE) libchewing-c LANG=chs

libv-c-cht:
	$(MAKE) libchewing-c LANG=cht

libchewing-c:
	@$(eval LANG := $(LANG))
	@$(eval WORK_DIR := "$(INTERMEDIATE_DIR)/LibChewing-$(shell echo $(LANG) | tr 'a-z' 'A-Z')")
	@$(eval BUILD_DIR_C := "$(RELEASE_DIR)/LibChewing-$(shell echo $(LANG) | tr 'a-z' 'A-Z')/C_Based")
	@mkdir -p "$(BUILD_DIR_C)/"
	@mkdir -p "$(WORK_DIR)/"
	@swift ./bin/cook_libchewing.swift $(LANG)
	@diff -u "$(WORK_DIR)/phone.cin" "$(WORK_DIR)/phone-CNS11643-complete.cin" --label phone.cin --label phone-CNS11643-complete.cin > "$(WORK_DIR)/phone.cin-CNS11643-complete.patch" || true
	@"$(CHEWING_C_INITIALIZER)" "$(WORK_DIR)/phone.cin" "$(WORK_DIR)/tsi.src"

# FOR INTERNAL USE

_remoteinstall-vchewing: macv
	@rsync -avx ./components/common/data-*.json $(RHOST):"Library/Containers/org.atelierInmu.inputmethod.vChewing/Data/Library/Application Support/vChewingFactoryData/"
	@test "$(RHOST)" && ssh $(RHOST) "pkill -HUP -f vChewing || echo Remote vChewing is not running" || true

gc:
	git reflog expire --expire=now --all ; git gc --prune=now --aggressive

gitcfg:
	cp .config_backup .git/config
