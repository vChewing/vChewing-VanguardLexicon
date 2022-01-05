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
	# 第一次讀取「tsi.csv」，主要用來統計 norm 數據。
	# norm 數據的統計公式著作權歸 MJHsieh 所有。
	lines = csv.DictReader(open("./Build/DerivedData/tsi.csv"), delimiter='\t')
	for entry in lines:
		norm += fscale**(len(entry['kanji'])/3-1)*float(entry['count'])
	# 第二次讀取「tsi.csv」，生成辭典以及 macOS 版威注音與小麥注音專用的 data.txt。
	dictionary = csv.DictReader(open("./Build/DerivedData/tsi.csv"), delimiter='\t')
	print ("正在生成 macOS 版威注音與小麥注音專用的 data.txt")
	try:
		handle = open('data.txt', "w")
	except IOError as e:
		print(("({})".format(e)))
	for entry in dictionary:
		# 將新酷音的詞語出現次數數據轉換成小麥引擎可讀的數據形式。
		# 對出現次數小於 1 的詞條，將 0 當成 0.5 來處理、以防止除零。
		# 統計公式著作權歸 MJHsieh 所有。
		if float(entry['count']) < 1:
			entry['freq'] = round(math.log(fscale**(len(entry['kanji'])/3-1)*0.5/norm, 10), 3)
		else:
			entry['freq'] = round(math.log(fscale**(len(entry['kanji'])/3-1)*float(entry['count'])/norm, 10), 3)
		handle.write('%s %s %s\n' % (entry['kanji'], entry['bpmf'], entry['freq']))
	handle.close()
	# 第三次讀取「tsi.csv」，生成辭典以及 macOS 版威注音與小麥注音專用的 data-plain-bpmf.txt。
	dictionary = csv.DictReader(open("./Build/DerivedData/tsi.csv"), delimiter='\t')
	print ("正在生成 macOS 版威注音與小麥注音專用的 data-plain-bpmf.txt")
	try:
		handle = open('data-plain-bpmf.txt', "w")
	except IOError as e:
		print(("({})".format(e)))
	for entry in dictionary:
		# ㄅ半注音的詞頻全部清零。
		entry['zerofreq'] = 0.0
		if len(entry['kanji']) == 1:
			handle.write('%s %s %s\n' % (entry['kanji'], entry['bpmf'], entry['zerofreq']))
	handle.close()
	# 第四次讀取「tsi.csv」，生成新酷音引擎與 Windows 版威注音專用的 tsi.src。
	dictionary = csv.DictReader(open("./Build/DerivedData/tsi.csv"), delimiter='\t')
	print ("正在生成新酷音引擎與 Windows 版威注音專用的 tsi.src")
	try:
		handle = open('tsi.src', "w")
	except IOError as e:
		print(("({})".format(e)))
	for entry in dictionary:
		# 新酷音引擎會自動將字詞的頻次數據換算成頻率數據，故這裡不做轉換。
		entry['bpmftsi'] = re.sub("-", " ", entry['bpmf'])
		handle.write('%s %s %s\n' % (entry['kanji'], entry['count'], entry['bpmftsi']))
	handle.close()
