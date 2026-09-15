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

# 確認建置目錄存在性
ifeq ($(OS),Windows_NT)
	BUILD_DIR_EXISTS := $(shell $(TEST) $(BUILD_DIR) -PathType Container && echo 1 || echo 0)
else
	BUILD_DIR_EXISTS := $(shell $(TEST) -d $(BUILD_DIR) && echo 1 || echo 0)
endif

.PHONY: format lint clean dockertest dockerrun \
        build510 clean510 \
        install install-vchewing macv \
        mcbpmf-all mcbpmf-chs mcbpmf-cht \
        mcbpmf-install-fcitx5 \
        libchewing-all libchewing-chs libchewing-cht \
        libchewing-rust libchewing-install \
        libchewing-all-c libchewing-c-chs libchewing-c-cht \
        libchewing-c libchewing-install-c \
        _remoteinstall-vchewing gc gitcfg \
        sort bleach prepare

# MARK: - General

format:
	@swiftformat --swiftversion 5.5 --indent 2 ./

lint:
	@echo "Running SwiftLint on tracked Swift files..."
	@files="$$(git ls-files -- '*.swift' ':!Build/**' ':!Packages/Build/**' ':!Packages/**/.build/')"; \
	if [ -z "$$files" ]; then \
		echo "No Swift files tracked by git."; \
	else \
		printf '%s\n' "$$files" | tr '\n' '\0' | \
		xargs -0 swiftlint lint --fix --autocorrect --config .swiftlint.yml --; \
	fi

clean:
	@$(RMDIR) "$(BUILD_DIR)"
	@$(RMDIR) ".$(PATHSEP).build"

dockertest:
	docker run --rm -v "$(shell pwd)":/workspace -w /workspace swift:latest swift test

dockerrun:
	docker run --rm -v "$(shell pwd)":/workspace -w /workspace swift:latest swift run

# MARK: - Swift 5.10 (legacy path)

# 用途：以 Swift 5.10 toolchain 驗本套件在該工具鏈下的 compilability（5.10 的 SwiftPM 會挑
# `Package@swift-5.swift`，6.x 側則挑 `Package.swift`）。
#
# 本套件之產物是 host 工具與資料庫、跨系統通用，故**不指定 SDK、也不釘 triple**：deployment target 交由
# manifest 之 `platforms` 決定（其為 nil 時即 SwiftPM 之該版本地板），編譯用的 SDK 亦交由當前開發環境決定。
# 換言之，本靶與 vChewing-macOS 側那套「Xcode 15 ＋ MacOSX13.3.sdk ＋ x86_64-apple-macosx10.10」的配對無關
# ——那套是為了把產物壓進 macOS 10.10 靜態庫，本套件不需要。
#
# 唯一仍須與 6.x 側分離的是 scratch path：5.10 的 SwiftPM 讀不懂新版 `workspace-state.json`（v7），共用即互踩。
#
# 另須把 **宿主** 的 `DEVELOPER_DIR` 指到一個 5.10 吃得下的 Xcode（預設 Xcode 15）。這不是本套件的 SDK 選擇，
# 而是 5.10 的 Clang importer 吃不下 Xcode 27 的 macOS 27 SDK——實測會先炸 `unknown argument:
# '-target-arch-variant'`，再於 `DarwinFoundation1.modulemap` 炸出成串 `could not build module
# '_DarwinFoundation1' / 'CoreFoundation' / 'Darwin'`。宿主換 Xcode 即可（`LEGACY_XCODE` 可覆寫）。
#
# 機理見 vChewing-DevLogs/Research/Phase217_SOP.md §二／§三。

# 5.10.1 工具鏈可能落在兩處：官方安裝器寫進 `/Library`，`swiftly` 則自管 `$HOME` 那份。兩者係同一
# 發行版、識別子相同，並存會令 Xcode 拒絕註冊而所有 `xcodebuild` 於套件解析前即敗。故自動擇一：
# 優先系統那份（不受 `swiftly uninstall` 影響），次取使用者空間那份。`?=` 仍可顯式覆寫。
LEGACY_TOOLCHAIN ?= $(firstword $(wildcard \
	/Library/Developer/Toolchains/swift-5.10.1-RELEASE.xctoolchain \
	$(HOME)/Library/Developer/Toolchains/swift-5.10.1-RELEASE.xctoolchain \
	))
LEGACY_XCODE ?= /Applications/Xcode-15.app/Contents/Developer
LEGACY_SCRATCH ?= .build/.legacy

build510:
	@export LC_ALL=C; export DEVELOPER_DIR="$(LEGACY_XCODE)"; \
	echo "Building VanguardLexicon with Swift 5.10…"; \
	"$(LEGACY_TOOLCHAIN)/usr/bin/swift" build \
		--package-path . \
		--scratch-path "$(LEGACY_SCRATCH)"

clean510:
	@$(RMDIR) "$(LEGACY_SCRATCH)"

# MARK: - macOS (vChewing)

install: install-vchewing clean

macv:
	swift run VCDataBuilder vanguardTextMap

vanguardTextMap-macOS:
ifeq ($(UNAME_S),Darwin)
	/usr/bin/swift run VCDataBuilder vanguardTextMap
endif

install-vchewing: macv
ifeq ($(OS),Windows_NT)
	@echo "Windows 不支援 vChewing。"
else
	@echo "\033[0;32m//$$(tput bold) macOS: 正在部署唯音輸入法核心語彙檔案……$$(tput sgr0)\033[0m"
	@"$(HOME)/Library/Input Methods/vChewing.app/Contents/MacOS/vChewing" --import-standalone-factory-lexicon "$(BUILD_DIR)/Release/vanguard-textmap/VanguardFactoryDict4Typing.txtMap"
	@$(PKILL) vChewing || echo "// vChewing is not running"
	@echo "\033[0;32m//$$(tput bold) macOS: 核心語彙檔案部署成功。$$(tput sgr0)\033[0m"
endif

# MARK: - McBopomofo (FCITX5-Linux)

mcbpmf-all: mcbpmf-chs mcbpmf-cht

mcbpmf-chs:
	$(MAKE) mcbpmf LANG=CHS

mcbpmf-cht:
	$(MAKE) mcbpmf LANG=CHT

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
	$(MAKE) libchewing-rust LANG=CHS

libchewing-cht:
	$(MAKE) libchewing-rust LANG=CHT

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
	$(MAKE) libchewing-c LANG=CHS

libchewing-c-cht:
	swift run VCDataBuilder chewingCBasedCHT
	$(MAKE) libchewing-c LANG=CHT

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
	@rsync -avx "$(BUILD_DIR)$(PATHSEP)Release$(PATHSEP)vanguard-textmap$(PATHSEP)VanguardFactoryDict4Typing.txtMap" $(RHOST):"Library/Containers/org.atelierInmu.inputmethod.vChewing/Data/Library/Application Support/vChewingFactoryData/"
	@$(TEST) "$(RHOST)" && ssh $(RHOST) "$(PKILL) vChewing || echo Remote vChewing is not running" || true
endif

gc:
	git reflog expire --expire=now --all ; git gc --prune=now --aggressive

gitcfg:
	@$(CP) ".config_backup" ".git$(PATHSEP)config"

sort:
	swift .$(PATHSEP)ValueAdds$(PATHSEP)SwiftScripts$(PATHSEP)RawPhraseFileContentSorter.swift

bleach:
	swift .$(PATHSEP)ValueAdds$(PATHSEP)SwiftScripts$(PATHSEP)Dict_MatchedContentRemover.swift

prepare:
	swift .$(PATHSEP)ValueAdds$(PATHSEP)SwiftScripts$(PATHSEP)Dict_NewPhrasesPreparer.swift
