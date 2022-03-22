SHELL := /bin/sh
.PHONY: all gc macv libv libv-chs libv-cht debug install install-vchewing _remoteinstall-vchewing clean BuildDir

all: macv winv phone.cin

clean:
	@rm -rf ./Build
	@rm -rf tsi-cht.src tsi-chs.src data-cht.txt data-chs.txt phone.cin phone.cin-CNS11643-complete.patch
		
install: install-vchewing clean

BuildDir:
	@mkdir -p ./Build

macv:
	@swift ./bin/cook_mac.swift

libv:
	swift ./bin/cook_libchewing.swift chs
	swift ./bin/cook_libchewing.swift cht

libv-chs: 
	@swift ./bin/cook_libchewing.swift chs
	@diff -u "./Build/phone-chs.cin" "./Build/phone-chs-ex.cin" --label phone.cin --label phone-CNS11643-complete.cin > "./phone.cin-CNS11643-complete.patch" || true
	@cp -a ./Build/tsi-chs.src ./tsi.src
	@cp -a ./Build/phone-chs.cin ./phone.cin

libv-cht: 
	@swift ./bin/cook_libchewing.swift cht
	@diff -u "./Build/phone-cht.cin" "./Build/phone-cht-ex.cin" --label phone.cin --label phone-CNS11643-complete.cin > "./phone.cin-CNS11643-complete.patch" || true
	@cp -a ./Build/tsi-cht.src ./tsi.src
	@cp -a ./Build/phone-cht.cin ./phone.cin

install-vchewing: macv
	@echo "\033[0;32m//$$(tput bold) macOS: 正在部署威注音核心語彙檔案……$$(tput sgr0)\033[0m"
	@cp -a data-chs.txt $(HOME)/Library/Input\ Methods/vChewing.app/Contents/Resources/
	@cp -a data-cht.txt $(HOME)/Library/Input\ Methods/vChewing.app/Contents/Resources/
	@cp -a ./components/common/data*.txt $(HOME)/Library/Input\ Methods/vChewing.app/Contents/Resources/
	@cp -a ./components/common/char-kanji-cns.txt $(HOME)/Library/Input\ Methods/vChewing.app/Contents/Resources/

	@pkill -HUP -f vChewing || echo "// vChewing is not running"
	@echo "\033[0;32m//$$(tput bold) macOS: 正在確保威注音不被 Gatekeeper 刁難……$$(tput sgr0)\033[0m"
	@/usr/bin/xattr -drs "com.apple.quarantine" $(HOME)/Library/Input\ Methods/vChewing.app
	@echo "\033[0;32m//$$(tput bold) macOS: 核心語彙檔案部署成功。$$(tput sgr0)\033[0m"

# FOR INTERNAL USE
debug:
	@rsync -avx ./phone.cin-CNS11643-complete.patch ./phone.cin ./tsi.src ~/Repos/libchewing/data/ || true
	@echo "\033[0;32m//$$(tput bold) libChewing: 開始偵錯測試。$$(tput sgr0)\033[0m"
	@make -f ~/Repos/libchewing/data/makefile  -C ~/Repos/libchewing/data/

_remoteinstall-vchewing: macv
	@rsync -avx data-chs.txt data-cht.txt $(RHOST):"Library/Input\ Methods/vChewing.app/Contents/Resources/"
	@rsync -avx ./components/common/data*.txt $(RHOST):"Library/Input\ Methods/vChewing.app/Contents/Resources/"
	@rsync -avx ./components/common/char-kanji-cns.txt.txt $(RHOST):"Library/Input\ Methods/vChewing.app/Contents/Resources/"
	@test "$(RHOST)" && ssh $(RHOST) "pkill -HUP -f vChewing || echo Remote vChewing is not running" || true

gc:
	git reflog expire --expire=now --all ; git gc --prune=now --aggressive
