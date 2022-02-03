SHELL := /bin/sh
.PHONY: all gc macv install install-vchewing _remotedeploy-vchewing deploy _deploy clean BuildDir tsi-chs tsi-cht phone.cin

all: macv wintsi phone.cin

clean:
	@rm -rf ./Build
	@rm -rf tsi-cht.src tsi-chs.src data-cht.txt data-chs.txt phone.cin phone.cin-CNS11643-complete.patch
		
install: install-vchewing clean

deploy: clean _deploy

#==== 以下是核心功能 ====#

BuildDir:
	@mkdir -p ./Build/DerivedData
	@mkdir -p ./Build/Products

#==== 下述两组功能，不算注释的话，前兩行内容完全雷同。 ====#

macv: tsi-chs tsi-cht
	@echo "\033[0;32m//$$(tput bold) macOS: 正在生成 data-chs.txt & data-cht.txt……$$(tput sgr0)\033[0m"
	@> ./data-chs.txt &&> ./data-cht.txt
	@./bin/cook_mac.py
	@echo "\033[0;32m//$$(tput bold) macOS: 正在插入標點符號與特殊表情……$$(tput sgr0)\033[0m"
	@env LC_COLLATE=C.UTF-8 awk 'NR>1 && FNR==1{print ""};1' ./components/common/macos-*.txt | sed -e "/^[[:space:]]*$$/d" >> ./data-chs.txt
	@env LC_COLLATE=C.UTF-8 awk 'NR>1 && FNR==1{print ""};1' ./components/common/macos-*.txt | sed -e "/^[[:space:]]*$$/d" >> ./data-cht.txt
	
winv: tsi-chs tsi-cht
	@echo "\033[0;32m//$$(tput bold) 非: 正在生成 tsi-chs.src && tsi-cht.src……$$(tput sgr0)\033[0m"
	@> ./tsi-chs.src &&> ./tsi-cht.src
	@./bin/cook_windows.py
	@env LC_COLLATE=C.UTF-8 cat ./Build/DerivedData/tsi-chs-notyetfinished.src | sort -rn -k2 >> ./tsi-chs.src
	@env LC_COLLATE=C.UTF-8 cat ./Build/DerivedData/tsi-cht-notyetfinished.src | sort -rn -k2 >> ./tsi-cht.src

tsi-chs: BuildDir
	@echo "\033[0;32m//$$(tput bold) 通用: 準備生成字詞總成讀音頻次表表頭及部分符號文字……$$(tput sgr0)\033[0m"
	@rm -f ./Build/DerivedData/tsi-chs.csv && echo $$'kanji\tcount\tbpmf' >> ./Build/DerivedData/tsi-chs.csv
	@env LC_COLLATE=C.UTF-8 awk 'NR>1 && FNR==1{print ""};1' ./components/common/char-misc-*.txt | uniq | sed -e "/^#/d;s/[^\s]([ ]{2,})[^\s]/ /g;s/ /$$(printf '\t')/g;" | cut -f1,2,3  | sed -e "/^[[:space:]]*$$/d" >> ./Build/DerivedData/tsi-chs.csv
	@echo "\033[0;32m//$$(tput bold) 通用: 正在生成簡體中文字詞總成讀音頻次表草稿（基礎集）……$$(tput sgr0)\033[0m"
	@env LC_COLLATE=C.UTF-8 cat ./components/common/char-kanji-core.txt | sort -u -k1 | sed -e "/^#/d;s/ /$$(printf '\t')/g" | sed -e "/^[[:space:]]*$$/d" | cut -f1,2,4 >> ./Build/DerivedData/tsi-chs.csv
	@echo "\033[0;32m//$$(tput bold) 通用: 正在插入詞組頻次表草稿（簡體中文）……$$(tput sgr0)\033[0m"
	@env LC_COLLATE=C.UTF-8 awk 'NR>1 && FNR==1{print ""};1' ./components/chs/phrases-*-chs.txt | sort -u -k1 | sed -e "/^#/d;s/$$(printf '\t')/ /;s/[^\s]([ ]{2,})[^\s]/ /g;s/ \n/\n/;s/ /$$(printf '\t')/;s/ /$$(printf '\t')/;s/ /-/g;" | sed -e "/^[[:space:]]*$$/d" >> ./Build/DerivedData/tsi-chs.csv

tsi-cht: BuildDir
	@echo "\033[0;32m//$$(tput bold) 通用: 準備生成字詞總成讀音頻次表表頭及部分符號文字……$$(tput sgr0)\033[0m"
	@rm -f ./Build/DerivedData/tsi-cht.csv && echo $$'kanji\tcount\tbpmf' >> ./Build/DerivedData/tsi-cht.csv
	@env LC_COLLATE=C.UTF-8 awk 'NR>1 && FNR==1{print ""};1' ./components/common/char-misc-*.txt | uniq | sed -e "/^#/d;s/[^\s]([ ]{2,})[^\s]/ /g;s/ /$$(printf '\t')/g;" | cut -f1,2,3  | sed -e "/^[[:space:]]*$$/d" >> ./Build/DerivedData/tsi-cht.csv
	@echo "\033[0;32m//$$(tput bold) 通用: 正在生成繁體中文字詞總成讀音頻次表草稿（基礎集）……$$(tput sgr0)\033[0m"
	@env LC_COLLATE=C.UTF-8 cat ./components/common/char-kanji-core.txt | sort -u -k1 | sed -e "/^#/d;s/ /$$(printf '\t')/g" | sed -e "/^[[:space:]]*$$/d" | cut -f1,3,4 >> ./Build/DerivedData/tsi-cht.csv
	@echo "\033[0;32m//$$(tput bold) 通用: 正在插入詞組頻次表草稿（繁體中文）……$$(tput sgr0)\033[0m"
	@env LC_COLLATE=C.UTF-8 awk 'NR>1 && FNR==1{print ""};1' ./components/cht/phrases-*-cht.txt | sort -u -k1 | sed -e "/^#/d;s/$$(printf '\t')/ /;s/[^\s]([ ]{2,})[^\s]/ /g;s/ \n/\n/;s/ /$$(printf '\t')/;s/ /$$(printf '\t')/;s/ /-/g;" | sed -e "/^[[:space:]]*$$/d" >> ./Build/DerivedData/tsi-cht.csv

#==== PHONE.CIN ====#
phone.cin: BuildDir
	@echo "\033[0;32m//$$(tput bold) 非: 正在生成漢字字音頻次表草稿（基礎集）……$$(tput sgr0)\033[0m"
	@> ./Build/DerivedData/phone.cinraw-core.txt
	@env LC_COLLATE=C.UTF-8 cat ./components/common/char-kanji-core.txt | sort -rn -k3 | sed -e "/^#/d;s/$$(printf '\t')/ /g;s/[^\s]([ ]{2,})[^\s]/ /g" | sed -e "/^[[:space:]]*$$/d" | awk 'BEGIN {FS=OFS=" "}; {print $$4,$$1}' | sed -f ./utilities/CONV-BPMF2KEY.SED > ./Build/DerivedData/phone.cinraw-core.txt
	@> ./Build/DerivedData/phone.cinraw-phrasesonly.txt
	@env LC_COLLATE=C.UTF-8 cat ./components/common/char-kanji-phrasesonly.txt | sort -u -k1 | sed -e "/^#/d;s/$$(printf '\t')/ /g;s/[^\s]([ ]{2,})[^\s]/ /g" | sed -e "/^[[:space:]]*$$/d" | awk 'BEGIN {FS=OFS=" "}; {print $$2,$$1}' | sed -f ./utilities/CONV-BPMF2KEY.SED >> ./Build/DerivedData/phone.cinraw-phrasesonly.txt

	@echo "\033[0;32m//$$(tput bold) 非: 正在生成漢字大千鍵序表草稿（全字庫）……$$(tput sgr0)\033[0m"
	@> ./Build/DerivedData/phone.cinraw-cns.txt
	@env LC_COLLATE=C.UTF-8 cat ./components/common/char-kanji-cns.txt | sort -u -k1 | sed -e "/^#/d;s/$$(printf '\t')/ /g;s/[^\s]([ ]{2,})[^\s]/ /g" | sed -e "/^[[:space:]]*$$/d" | awk 'BEGIN {FS=OFS=" "}; {print $$2,$$1}' | sed -f ./utilities/CONV-BPMF2KEY.SED > ./Build/DerivedData/phone.cinraw-cns.txt

	@echo "\033[0;32m//$$(tput bold) 非: 正在生成漢字大千鍵序表草稿（符號與注音）……$$(tput sgr0)\033[0m"
	@> ./Build/DerivedData/phone.cinraw-misc.txt
	@env LC_COLLATE=C.UTF-8 awk 'NR>1 && FNR==1{print ""};1' ./components/common/char-misc-*.txt | sort -u -k1 | sed -e "/^#/d;s/$$(printf '\t')/ /g;s/[^\s]([ ]{2,})[^\s]/ /g" | sed -e "/^[[:space:]]*$$/d" | awk 'BEGIN {FS=OFS=" "}; {print $$5,$$1}' > ./Build/DerivedData/phone.cinraw-misc.txt

	@echo "\033[0;32m//$$(tput bold) 非: 正在拼裝漢字大千鍵序 CIN 表（基礎集）……$$(tput sgr0)\033[0m"
	@cp -a ./components/common/phone-header.txt ./Build/Products/phone.cin
	@cat ./Build/DerivedData/phone.cinraw-misc.txt | sort -u -k2 >> ./Build/Products/phone.cin
	@cat ./Build/DerivedData/phone.cinraw-core.txt | uniq >> ./Build/Products/phone.cin
	@cat ./Build/DerivedData/phone.cinraw-phrasesonly.txt | uniq >> ./Build/Products/phone.cin
	@echo "%chardef  end" >> ./Build/Products/phone.cin
	@sed -i '' -e "/^[[:space:]]*$$/d" ./Build/Products/phone.cin
	@cp -a ./Build/Products/phone.cin ./phone.cin

	@echo "\033[0;32m//$$(tput bold) 非: 正在拼裝漢字大千鍵序 CIN 表（全字庫）……$$(tput sgr0)\033[0m"
	@cp -a ./components/common/phone-header.txt ./Build/Products/phone-CNS11643-complete.cin
	@cat ./Build/DerivedData/phone.cinraw-misc.txt | sort -u -k2 >> ./Build/Products/phone-CNS11643-complete.cin
	@cat ./Build/DerivedData/phone.cinraw-core.txt | uniq >> ./Build/Products/phone-CNS11643-complete.cin
	@cat ./Build/DerivedData/phone.cinraw-phrasesonly.txt | uniq >> ./Build/Products/phone-CNS11643-complete.cin
	@cat ./Build/DerivedData/phone.cinraw-cns.txt | uniq >> ./Build/Products/phone-CNS11643-complete.cin
	@echo "%chardef  end" >> ./Build/Products/phone-CNS11643-complete.cin
	@sed -i '' -e "/^[[:space:]]*$$/d" ./Build/Products/phone-CNS11643-complete.cin

	@echo "\033[0;32m//$$(tput bold) 非: 正在生成針對基礎集的全字庫差分增補檔案……$$(tput sgr0)\033[0m"
	@diff -u "./Build/Products/phone.cin" "./Build/Products/phone-CNS11643-complete.cin" --label phone.cin --label phone-CNS11643-complete.cin > "./phone.cin-CNS11643-complete.patch" || true

# FOR INTERNAL USE
install-vchewing: macv
	@pkill -HUP -f vChewing || echo "// Deploying Dictionary files for vChewing...."
	rm $(HOME)/Library/Input\ Methods/vChewing.app/Contents/Resources/data*.txt || true
	@cp -a data-chs.txt $(HOME)/Library/Input\ Methods/vChewing.app/Contents/Resources/
	@cp -a data-cht.txt $(HOME)/Library/Input\ Methods/vChewing.app/Contents/Resources/
	@pkill -HUP -f vChewing || echo "// vChewing is not running"

_remotedeploy-vchewing: macv
	@rsync -avx data-chs.txt data-cht.txt $(RHOST):"Library/Input\ Methods/vChewing.app/Contents/Resources/"
	@test "$(RHOST)" && ssh $(RHOST) "pkill -HUP -f vChewing || echo Remote vChewing is not running" || true

_deploy:
	cp -R ./* ~/Repos/vChewing-CHS/Source/Data/ || true
	rm -rf ~/Repos/vChewing-CHS/Source/Data/Build || true

gc:
	git reflog expire --expire=now --all ; git gc --prune=now --aggressive
