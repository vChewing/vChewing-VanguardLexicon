# 系統平台判定
ifeq ($(OS),Windows_NT)
	SHELL := powershell.exe
	.SHELLFLAGS := -NoProfile -Command
	RMDIR := Remove-Item -Recurse -Force
	CP := Copy-Item -Force
	MKDIR := New-Item -ItemType Directory -Force
	PKILL := Stop-Process -Name
	TEST := Test-Path
	PATHSEP := \\
else
	SHELL := /bin/sh
	RMDIR := rm -rf
	CP := cp -a
	MKDIR := mkdir -p
	PKILL := pkill
	TEST := test
	PATHSEP := /
endif

# 目錄常數定義
BUILD_DIR := $(shell pwd)$(PATHSEP)Build
RELEASE_DIR := $(BUILD_DIR)$(PATHSEP)Release
INTERMEDIATE_DIR := $(BUILD_DIR)$(PATHSEP)Intermediate
CHEWING_C_INITIALIZER := $(shell pwd)$(PATHSEP)bin$(PATHSEP)libchewing-database-initializer$(PATHSEP)init_database

# 確認建置目錄存在性
ifeq ($(OS),Windows_NT)
	BUILD_DIR_EXISTS := $(shell $(TEST) $(BUILD_DIR) -PathType Container && echo 1 || echo 0)
else
	BUILD_DIR_EXISTS := $(shell $(TEST) -d $(BUILD_DIR) && echo 1 || echo 0)
endif

.PHONY: format lint clean dockertest dockerrun \
        install install-vchewing macv \
        mcbpmf-all mcbpmf-chs mcbpmf-cht \
        mcbpmf-install-fcitx5 \
        libchewing-all libchewing-chs libchewing-cht \
        libchewing-rust libchewing-install \
        libchewing-all-c libchewing-c-chs libchewing-c-cht \
        libchewing-c libchewing-install-c \
        _remoteinstall-vchewing gc gitcfg

# MARK: - General

format:
	@swiftformat --swiftversion 5.5 --indent 2 ./

lint:
	@git ls-files --exclude-standard | grep -E '\.swift$$' | swiftlint --fix --autocorrect

clean:
	@$(RMDIR) "$(BUILD_DIR)"
	@$(RMDIR) ".$(PATHSEP).build"

dockertest:
	docker run --rm -v "$(shell pwd)":/workspace -w /workspace swift:latest swift test

dockerrun:
	docker run --rm -v "$(shell pwd)":/workspace -w /workspace swift:latest swift run

# MARK: - macOS (vChewing)

install: install-vchewing clean

macv:
	swift run VCDataBuilder vanguardSQLLegacy

install-vchewing: macv
ifeq ($(OS),Windows_NT)
	@echo "Windows 不支援 vChewing。"
else
	@echo "\033[0;32m//$$(tput bold) macOS: 正在部署威注音核心語彙檔案……$$(tput sgr0)\033[0m"
	@$(MKDIR) "$(HOME)/Library/Containers/org.atelierInmu.inputmethod.vChewing/Data/Library/Application Support/vChewingFactoryData/"
	@$(CP) "$(BUILD_DIR)/Release/vanguardSQL-Legacy/vChewingFactoryDatabase.sqlite" "$(HOME)/Library/Containers/org.atelierInmu.inputmethod.vChewing/Data/Library/Application Support/vChewingFactoryData/"
	@$(PKILL) vChewing || echo "// vChewing is not running"
	@echo "\033[0;32m//$$(tput bold) macOS: 核心語彙檔案部署成功。$$(tput sgr0)\033[0m"
endif

# MARK: - McBopomofo (FCITX5-Linux)

mcbpmf-all: mcbpmf-chs mcbpmf-cht

mcbpmf-chs:
	$(MAKE) mcbpmf LANG=chs

mcbpmf-cht:
	$(MAKE) mcbpmf LANG=cht

mcbpmf:
	@$(eval LANG := $(shell echo $(LANG) | tr 'a-z' 'A-Z'))
	swift run VCDataBuilder chewingRust$(LANG)

mcbpmf-install-fcitx5: mcbpmf
	@$(eval DEPLOY_DIR_MCBPMF_LINUX_FCITX5 := "/usr/share/fcitx5/data/")
	@$(eval LANG := $(shell echo $(LANG) | tr 'A-Z' 'a-z'))
	@$(eval BUILD_DIR_MCBPMF := "$(RELEASE_DIR)$(PATHSEP)mcbopomofo-$(shell echo $(LANG) | tr 'A-Z' 'a-z')")
ifeq ($(OS),Windows_NT)
	@echo "Windows 不支援 McBopomofo。"
else
	@$(MKDIR) $(DEPLOY_DIR_MCBPMF_LINUX_FCITX5)
	@$(CP) "$(BUILD_DIR_MCBPMF)$(PATHSEP)data.txt" $(DEPLOY_DIR_MCBPMF_LINUX_FCITX5)
	@echo "\033[0;32m//$$(tput bold) 已將詞庫檔案部署至 $(DEPLOY_DIR_MCBPMF_LINUX_FCITX5) 目錄下。$$(tput sgr0)\033[0m"
endif

# MARK: - LibChewing (Rust-Based)

libchewing-all: libchewing-chs libchewing-cht

libchewing-chs:
	$(MAKE) libchewing-rust LANG=chs

libchewing-cht:
	$(MAKE) libchewing-rust LANG=cht

libchewing-rust:
	@$(eval LANG := $(shell echo $(LANG) | tr 'a-z' 'A-Z'))
	swift run VCDataBuilder chewingRust$(LANG)

libchewing-install: libchewing-rust
	@$(eval DEPLOY_DIR_CHEWINGR_LINUX := "$(HOME)/.config/chewing")
	@$(eval DEPLOY_DIR_CHEWINGR_WIN := "C:$(PATHSEP)Users$(PATHSEP)$(USERNAME)$(PATHSEP)AppData$(PATHSEP)Roaming$(PATHSEP)chewing$(PATHSEP)Chewing$(PATHSEP)data")
	@$(eval DEPLOY_DIR_CHEWINGR_WIN_LEGACY := "C:$(PATHSEP)Users$(PATHSEP)$(USERNAME)$(PATHSEP)ChewingTextService")
	@$(eval LANG := $(shell echo $(LANG) | tr 'A-Z' 'a-z'))
	@$(eval BUILD_DIR_CHEWINGR := "$(RELEASE_DIR)$(PATHSEP)chewing-rust-$(shell echo $(LANG) | tr 'A-Z' 'a-z')")
ifeq ($(OS),Windows_NT)
	@$(MKDIR) "$(DEPLOY_DIR_CHEWINGR_WIN)"
	@$(CP) "$(BUILD_DIR_CHEWINGR)$(PATHSEP)tsi.dat","$(BUILD_DIR_CHEWINGR)$(PATHSEP)word.dat" "$(DEPLOY_DIR_CHEWINGR_WIN)"
	@$(MKDIR) "$(DEPLOY_DIR_CHEWINGR_WIN_LEGACY)"
	@$(CP) "$(BUILD_DIR_CHEWINGR)$(PATHSEP)tsi.dat","$(BUILD_DIR_CHEWINGR)$(PATHSEP)word.dat" "$(DEPLOY_DIR_CHEWINGR_WIN_LEGACY)"
	@echo "已將 $(LANG) 詞庫檔案部署至 $(DEPLOY_DIR_CHEWINGR_WIN) 和 $(DEPLOY_DIR_CHEWINGR_WIN_LEGACY) 目錄下。"
else
	@$(MKDIR) "$(DEPLOY_DIR_CHEWINGR_LINUX)"
	@$(CP) "$(BUILD_DIR_CHEWINGR)$(PATHSEP)tsi.dat" "$(BUILD_DIR_CHEWINGR)$(PATHSEP)word.dat" "$(DEPLOY_DIR_CHEWINGR_LINUX)"
	@echo "\033[0;32m//$$(tput bold) 已將 $(LANG) 詞庫檔案部署至 $(DEPLOY_DIR_CHEWINGR_LINUX) 目錄下。$$(tput sgr0)\033[0m"
endif

# MARK: - LibChewing (C-Based)

libchewing-all-c: libchewing-c-chs libchewing-c-cht

libchewing-c-chs:
	swift run VCDataBuilder chewingCBasedCHS
	$(MAKE) libchewing-c LANG=chs

libchewing-c-cht:
	swift run VCDataBuilder chewingCBasedCHT
	$(MAKE) libchewing-c LANG=cht

libchewing-c:
	@$(eval LANG := $(shell echo $(LANG) | tr 'a-z' 'A-Z'))
	swift run VCDataBuilder chewingCBased$(LANG)

libchewing-install-c: libchewing-c
	@$(eval DEPLOY_DIR_CHEWINGC_LINUX := "/usr/share/libchewing/")
	@$(eval DEPLOY_DIR_CHEWINGC_WIN := "C:$(PATHSEP)Program Files (x86)$(PATHSEP)ChewingTextService$(PATHSEP)Dictionary")
	@$(eval LANG := $(shell echo $(LANG) | tr 'A-Z' 'a-z'))
	@$(eval BUILD_DIR_CHEWINGC := "$(RELEASE_DIR)$(PATHSEP)chewing-cbased-$(shell echo $(LANG) | tr 'A-Z' 'a-z')")
ifeq ($(OS),Windows_NT)
	@$(MKDIR) "$(DEPLOY_DIR_CHEWINGC_WIN)"
	@$(CP) "$(BUILD_DIR_CHEWINGC)$(PATHSEP)dictionary.dat","$(BUILD_DIR_CHEWINGC)$(PATHSEP)index_tree.dat" "$(DEPLOY_DIR_CHEWINGC_WIN)"
	@echo "已將 $(LANG) 詞庫檔案部署至 $(DEPLOY_DIR_CHEWINGC_WIN) 目錄下。"
else
	@$(MKDIR) "$(DEPLOY_DIR_CHEWINGC_LINUX)"
	@$(CP) "$(BUILD_DIR_CHEWINGC)$(PATHSEP)dictionary.dat" "$(BUILD_DIR_CHEWINGC)$(PATHSEP)index_tree.dat" "$(DEPLOY_DIR_CHEWINGC_LINUX)"
	@echo "\033[0;32m//$$(tput bold) 已將 $(LANG) 詞庫檔案部署至 $(DEPLOY_DIR_CHEWINGC_LINUX) 目錄下。$$(tput sgr0)\033[0m"
endif

# FOR INTERNAL USE

_remoteinstall-vchewing: macv
ifeq ($(OS),Windows_NT)
	@echo "Windows 不支援遠端安裝 vChewing 辭典。"
else
	@rsync -avx "$(BUILD_DIR)$(PATHSEP)Release$(PATHSEP)vanguardSQL-Legacy$(PATHSEP)vChewingFactoryDatabase.sqlite" $(RHOST):"Library/Containers/org.atelierInmu.inputmethod.vChewing/Data/Library/Application Support/vChewingFactoryData/"
	@$(TEST) "$(RHOST)" && ssh $(RHOST) "$(PKILL) vChewing || echo Remote vChewing is not running" || true
endif

gc:
	git reflog expire --expire=now --all ; git gc --prune=now --aggressive

gitcfg:
	@$(CP) ".config_backup" ".git$(PATHSEP)config"
