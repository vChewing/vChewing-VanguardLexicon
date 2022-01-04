SHELL := /bin/sh
.PHONY: all gc CHSBuild install install-vchewing install-mcbopomo _remotedeploy-mcbopomo _remotedeploy-vchewing deploy _deploy clean semiclean BuildDir concat-kanji-core tsi-initial tsi-chs tsi-cht phone.cin

all: tsi-cht phone.cin

CHSBuild: tsi-chs phone.cin

vChewing-macOSBuild: tsi-chs tsi-cht

clean:
	@rm -rf ./Build
	@rm -rf tsi.src tsi-chs.src data.txt data-chs.txt data-plain-bpmf.txt data-plain-bpmf-chs.txt phone.cin phone-CNS11643-complete.cin
		
install: install-vchewing install-mcbopomo clean

deploy: clean _deploy

#==== 以下是核心功能 ====#

BuildDir:
	@mkdir -p ./Build/DerivedData
	@mkdir -p ./Build/Products

#==== 下述两组功能，不算注释的话，前兩行内容完全雷同。 ====#

tsi-chs: BuildDir
	@echo "\033[0;32m//$$(tput bold) 通用: 準備生成字詞總成讀音頻次表表頭及部分符號文字……$$(tput sgr0)\033[0m"
	@rm -f ./Build/DerivedData/tsi.csv && echo $$'kanji\tcount\tbpmf' >> ./Build/DerivedData/tsi.csv
	@env LC_COLLATE=C.UTF-8 awk 'NR>1 && FNR==1{print ""};1' ./components/common/char-misc-*.txt | uniq | sed -e "/^#/d;s/[^\s]([ ]{2,})[^\s]/ /g;s/ /\t/g;" | cut -f1,2,3  | sed -e "/^[[:space:]]*$$/d" >> ./Build/DerivedData/tsi.csv
	@echo "\033[0;32m//$$(tput bold) 通用: 正在生成簡體中文字詞總成讀音頻次表草稿（基礎集）……$$(tput sgr0)\033[0m"
	@env LC_COLLATE=C.UTF-8 cat ./components/common/char-kanji-core.txt | sort -u -k1 | sed -e "/^#/d;s/ /\t/g" | sed -e "/^[[:space:]]*$$/d" | cut -f1,2,4 >> ./Build/DerivedData/tsi.csv
	@echo "\033[0;32m//$$(tput bold) 通用: 正在插入詞組頻次表草稿（簡體中文）……$$(tput sgr0)\033[0m"
	@env LC_COLLATE=C.UTF-8 awk 'NR>1 && FNR==1{print ""};1' ./components/chs/phrases-*-chs.txt | sort -u -k1 | sed -e "/^#/d;s/\t/ /;s/[^\s]([ ]{2,})[^\s]/ /g;s/ \n/\n/;s/ /\t/;s/ /\t/;s/ /-/g;" | sed -e "/^[[:space:]]*$$/d" >> ./Build/DerivedData/tsi.csv
	@echo "\033[0;32m//$$(tput bold) 通用: 正在生成 tsi.src & data.txt & data-plain-bpmf.txt（簡體中文）……$$(tput sgr0)\033[0m"
	@> ./data.txt &&> ./data-plain-bpmf.txt &&> ./tsi.src
	@./bin/cook_neo.py
	@mv ./data.txt ./data-chs.txt && mv ./data-plain-bpmf.txt ./data-plain-bpmf-chs.txt && mv ./tsi.src ./tsi-chs.src
	@echo "\033[0;32m//$$(tput bold) macOS: 正在插入標點符號與特殊表情……$$(tput sgr0)\033[0m"
	@env LC_COLLATE=C.UTF-8 awk 'NR>1 && FNR==1{print ""};1' ./components/common/macos-*.txt | sed -e "/^[[:space:]]*$$/d" >> ./data-chs.txt
	@env LC_COLLATE=C.UTF-8 awk 'NR>1 && FNR==1{print ""};1' ./components/common/macos-*.txt | sed -e "/^[[:space:]]*$$/d" | awk 'BEGIN {FS=OFS=" "}; {print $$1,$$2,"0.0"}' >> ./data-plain-bpmf-chs.txt

tsi-cht: BuildDir
	@echo "\033[0;32m//$$(tput bold) 通用: 準備生成字詞總成讀音頻次表表頭及部分符號文字……$$(tput sgr0)\033[0m"
	@rm -f ./Build/DerivedData/tsi.csv && echo $$'kanji\tcount\tbpmf' >> ./Build/DerivedData/tsi.csv
	@env LC_COLLATE=C.UTF-8 awk 'NR>1 && FNR==1{print ""};1' ./components/common/char-misc-*.txt | uniq | sed -e "/^#/d;s/[^\s]([ ]{2,})[^\s]/ /g;s/ /\t/g;" | cut -f1,2,3  | sed -e "/^[[:space:]]*$$/d" >> ./Build/DerivedData/tsi.csv
	@echo "\033[0;32m//$$(tput bold) 通用: 正在生成繁體中文字詞總成讀音頻次表草稿（基礎集）……$$(tput sgr0)\033[0m"
	@env LC_COLLATE=C.UTF-8 cat ./components/common/char-kanji-core.txt | sort -u -k1 | sed -e "/^#/d;s/ /\t/g" | sed -e "/^[[:space:]]*$$/d" | cut -f1,3,4 >> ./Build/DerivedData/tsi.csv
	@echo "\033[0;32m//$$(tput bold) 通用: 正在插入詞組頻次表草稿（繁體中文）……$$(tput sgr0)\033[0m"
	@env LC_COLLATE=C.UTF-8 awk 'NR>1 && FNR==1{print ""};1' ./components/cht/phrases-*-cht.txt | sort -u -k1 | sed -e "/^#/d;s/\t/ /;s/[^\s]([ ]{2,})[^\s]/ /g;s/ \n/\n/;s/ /\t/;s/ /\t/;s/ /-/g;" | sed -e "/^[[:space:]]*$$/d" >> ./Build/DerivedData/tsi.csv
	@echo "\033[0;32m//$$(tput bold) 通用: 正在生成 tsi.src & data.txt & data-plain-bpmf.txt（繁體中文）……$$(tput sgr0)\033[0m"
	@> ./data.txt &&> ./data-plain-bpmf.txt &&> ./tsi.src
	@./bin/cook_neo.py
	@echo "\033[0;32m//$$(tput bold) macOS: 正在插入標點符號與特殊表情……$$(tput sgr0)\033[0m"
	@env LC_COLLATE=C.UTF-8 awk 'NR>1 && FNR==1{print ""};1' ./components/common/macos-*.txt | sed -e "/^[[:space:]]*$$/d" >> ./data.txt
	@env LC_COLLATE=C.UTF-8 awk 'NR>1 && FNR==1{print ""};1' ./components/common/macos-*.txt | sed -e "/^[[:space:]]*$$/d" | awk 'BEGIN {FS=OFS=" "}; {print $$1,$$2,"0.0"}' >> ./data-plain-bpmf.txt

#==== PHONE.CIN ====#
phone.cin: BuildDir
	@echo "\033[0;32m//$$(tput bold) 非: 正在生成漢字字音頻次表草稿（基礎集）……$$(tput sgr0)\033[0m"
	@> ./Build/DerivedData/phone.cinraw-core.txt
	@env LC_COLLATE=C.UTF-8 cat ./components/common/char-kanji-core.txt | sort -u -k1 | sed -e "/^#/d;s/\t/ /g;s/[^\s]([ ]{2,})[^\s]/ /g" | sed -e "/^[[:space:]]*$$/d" | awk 'BEGIN {FS=OFS=" "}; {print $$4,$$1}' | sed -f ./utilities/CONV-BPMF2KEY.SED > ./Build/DerivedData/phone.cinraw-core.txt

	@echo "\033[0;32m//$$(tput bold) 非: 正在生成漢字大千鍵序表草稿（全字庫）……$$(tput sgr0)\033[0m"
	@> ./Build/DerivedData/phone.cinraw-cns.txt
	@env LC_COLLATE=C.UTF-8 cat ./components/common/char-kanji-cns.txt | sort -u -k1 | sed -e "/^#/d;s/\t/ /g;s/[^\s]([ ]{2,})[^\s]/ /g" | sed -e "/^[[:space:]]*$$/d" | awk 'BEGIN {FS=OFS=" "}; {print $$2,$$1}' | sed -f ./utilities/CONV-BPMF2KEY.SED > ./Build/DerivedData/phone.cinraw-cns.txt

	@echo "\033[0;32m//$$(tput bold) 非: 正在生成漢字大千鍵序表草稿（符號與注音）……$$(tput sgr0)\033[0m"
	@> ./Build/DerivedData/phone.cinraw-misc.txt
	@env LC_COLLATE=C.UTF-8 awk 'NR>1 && FNR==1{print ""};1' ./components/common/char-misc-*.txt | sort -u -k1 | sed -e "/^#/d;s/\t/ /g;s/[^\s]([ ]{2,})[^\s]/ /g" | sed -e "/^[[:space:]]*$$/d" | awk 'BEGIN {FS=OFS=" "}; {print $$5,$$1}' > ./Build/DerivedData/phone.cinraw-misc.txt

	@echo "\033[0;32m//$$(tput bold) 非: 正在拼裝漢字大千鍵序 CIN 表（基礎集）……$$(tput sgr0)\033[0m"
	@cp -a ./components/common/phone-header.txt ./Build/Products/phone.cin
	@cat ./Build/DerivedData/phone.cinraw-misc.txt | sort -u -k2 >> ./Build/Products/phone.cin
	@cat ./Build/DerivedData/phone.cinraw-core.txt | sort -u -k1 >> ./Build/Products/phone.cin
	@echo "%chardef  end" >> ./Build/Products/phone.cin
	@sed -i '' -e "/^[[:space:]]*$$/d" ./Build/Products/phone.cin
	@cp -a ./Build/Products/phone.cin ./phone.cin

	@echo "\033[0;32m//$$(tput bold) 非: 正在拼裝漢字大千鍵序 CIN 表（全字庫）……$$(tput sgr0)\033[0m"
	@cp -a ./components/common/phone-header.txt ./Build/Products/phone-CNS11643-complete.cin
	@cat ./Build/DerivedData/phone.cinraw-misc.txt | sort -u -k2 >> ./Build/Products/phone-CNS11643-complete.cin
	@env LC_COLLATE=C.UTF-8 awk 'NR>1 && FNR==1{print ""};1' ./Build/DerivedData/phone.cinraw-c*.txt | sort -u -k1 >> ./Build/Products/phone-CNS11643-complete.cin
	@echo "%chardef  end" >> ./Build/Products/phone-CNS11643-complete.cin
	@sed -i '' -e "/^[[:space:]]*$$/d" ./Build/Products/phone-CNS11643-complete.cin

	@echo "\033[0;32m//$$(tput bold) 非: 正在生成針對基礎集的全字庫差分增補檔案……$$(tput sgr0)\033[0m"
	@diff -u "./Build/Products/phone.cin" "./Build/Products/phone-CNS11643-complete.cin" --label phone.cin --label phone-CNS11643-complete.cin > "./phone.cin-CNS11643-complete.patch" || true

# FOR INTERNAL USE
install-mcbopomo: tsi-cht
	@pkill -HUP -f McBopomofo || echo "// Deploying Dictionary files for McBopomofo...."
	rm $(HOME)/Library/Input\ Methods/McBopomofo.app/Contents/Resources/data*.txt || true
	@cp -a data.txt $(HOME)/Library/Input\ Methods/McBopomofo.app/Contents/Resources/data.txt
	@cp -a data-plain-bpmf.txt $(HOME)/Library/Input\ Methods/McBopomofo.app/Contents/Resources/data-plain-bpmf.txt
	@pkill -HUP -f McBopomofo || echo "// McBopomofo is not running"

_remotedeploy-mcbopomo: _install
	@rsync -avx data.txt data-plain-bpmf.txt $(RHOST):"Library/Input\ Methods/McBopomofo.app/Contents/Resources/"
	@test "$(RHOST)" && ssh $(RHOST) "pkill -HUP -f McBopomofo || echo Remote McBopomofo is not running" || true

install-vchewing: tsi-chs
	@pkill -HUP -f McBopomofo || echo "// Deploying Dictionary files for vChewing...."
	rm $(HOME)/Library/Input\ Methods/vChewing.app/Contents/Resources/data*.txt || true
	@cp -a data-chs.txt $(HOME)/Library/Input\ Methods/vChewing.app/Contents/Resources/
	@cp -a data-plain-bpmf-chs.txt $(HOME)/Library/Input\ Methods/vChewing.app/Contents/Resources/
	@pkill -HUP -f vChewing || echo "// vChewing is not running"

_remotedeploy-vchewing: _install
	@rsync -avx data-chs.txt data-plain-bpmf-chs.txt $(RHOST):"Library/Input\ Methods/vChewing.app/Contents/Resources/"
	@test "$(RHOST)" && ssh $(RHOST) "pkill -HUP -f vChewing || echo Remote vChewing is not running" || true

_deploy:
	cp -R ./* ~/Repos/vChewing-CHS/Source/Data/ || true
	rm -rf ~/Repos/vChewing-CHS/Source/Data/Build || true
	cp -R ./* ~/Repos/McBopomofo-Safe/Source/Data/ || true
	rm -rf ~/Repos/McBopomofo-Safe/Source/Data/Build || true

gc:
	git reflog expire --expire=now --all ; git gc --prune=now --aggressive
