#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import re
import sys
import csv
import math
__author__ = 'Programmed by Shiki Suen. (calculation formulas by MJHsieh.)'

mydict = {}
norm	  = 0.0
fscale	= 2.7

if __name__ == '__main__':
	# zh-Hant
	# 第一次讀取「tsi-cht.csv」，主要用來統計 norm 數據。
	# norm 數據的統計公式著作權歸 MJHsieh 所有。
	lines = csv.DictReader(open("./Build/DerivedData/tsi-cht.csv"), delimiter='\t')
	for entry in lines:
		norm += fscale**(len(entry['kanji'])/3-1)*float(entry['count'])
	# 第二次讀取「tsi-cht.csv」，生成新酷音引擎與 Windows 版威注音專用的 tsi-cht.src。
	dictionary = csv.DictReader(open("./Build/DerivedData/tsi-cht.csv"), delimiter='\t')
	print ("正在生成新酷音引擎與 Windows 版威注音專用的 tsi-cht.src")
	try:
		handle = open('./Build/DerivedData/tsi-cht-notyetfinished.src', "w")
	except IOError as e:
		print(("({})".format(e)))
	for entry in dictionary:
		# 新酷音引擎會自動將字詞的頻次數據換算成頻率數據，故這裡不做轉換。
		entry['bpmftsi'] = re.sub("-", " ", entry['bpmf'])
		handle.write('%s %s %s\n' % (entry['kanji'], entry['count'], entry['bpmftsi']))
	handle.close()

	# zh-Hans
	# 第一次讀取「tsi-chs.csv」，主要用來統計 norm 數據。
	# norm 數據的統計公式著作權歸 MJHsieh 所有。
	lines = csv.DictReader(open("./Build/DerivedData/tsi-chs.csv"), delimiter='\t')
	for entry in lines:
		norm += fscale**(len(entry['kanji'])/3-1)*float(entry['count'])
	# 第二次讀取「tsi-chs.csv」，生成新酷音引擎與 Windows 版威注音專用的 tsi-chs.src。
	dictionary = csv.DictReader(open("./Build/DerivedData/tsi-chs.csv"), delimiter='\t')
	print ("正在生成新酷音引擎與 Windows 版威注音專用的 tsi-chs.src")
	try:
		handle = open('./Build/DerivedData/tsi-chs-notyetfinished.src', "w")
	except IOError as e:
		print(("({})".format(e)))
	for entry in dictionary:
		# 新酷音引擎會自動將字詞的頻次數據換算成頻率數據，故這裡不做轉換。
		entry['bpmftsi'] = re.sub("-", " ", entry['bpmf'])
		handle.write('%s %s %s\n' % (entry['kanji'], entry['count'], entry['bpmftsi']))
	handle.close()
