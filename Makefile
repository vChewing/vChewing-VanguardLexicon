.PHONY: all

all: 
	make all --file=./Makefile-CHT

# 威注音现阶段预设简体中文输入法，所以在没有传入参数的情况下只会生成简体中文输入模式的数据。

CHSBuild: 
	make all --file=./Makefile-CHS

clean:
	@echo "\033[0;32m//$$(tput bold) 清理任何生成的档案……$$(tput sgr0)\033[0m"
	@rm -f data.txt data-plain-bpmf.txt phrase.list PhraseFreq.txt BPMFBase.txt BPMFMappings.txt phrase.occ tmp || true
	@rm -f ./rime-headers/body*.yaml || true

# 总分发模式，要求同时安装小麦注音与威注音
deploy: install clean
	cp -R ./* ~/Repos/vChewing-CHS/Source/Data/ || true
	rm -rf ~/Repos/vChewing-CHS/Source/Data/Build || true
	cp -R ./* ~/Repos/McBopomofo-Safe/Source/Data/ || true
	rm -rf ~/Repos/McBopomofo-Safe/Source/Data/Build || true


# 简体繁体版词库分别编译后分别安装给威注音与小麦注音
install: install-vchewing install-mcbopomo

install-vchewing: 
	make _install --file=./Makefile-CHS
	make clean --file=./Makefile-CHS

install-mcbopomo: 
	make _install --file=./Makefile-CHT
	make clean --file=./Makefile-CHT

install-rime:
	make rime-deploy --file=./Makefile-Rime
