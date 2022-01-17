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
	# 第二次讀取「tsi-cht.csv」，生成辭典以及 macOS 版威注音專用的 data-cht.txt。
	dictionary = csv.DictReader(open("./Build/DerivedData/tsi-cht.csv"), delimiter='\t')
	print ("正在生成 macOS 版威注音與小麥注音專用的 data-cht.txt")
	try:
		handle = open('data-cht.txt', "w")
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

	# zh-Hans
	# 第一次讀取「tsi-chs.csv」，主要用來統計 norm 數據。
	# norm 數據的統計公式著作權歸 MJHsieh 所有。
	lines = csv.DictReader(open("./Build/DerivedData/tsi-chs.csv"), delimiter='\t')
	for entry in lines:
		norm += fscale**(len(entry['kanji'])/3-1)*float(entry['count'])
	# 第二次讀取「tsi-chs.csv」，生成辭典以及 macOS 版威注音專用的 data-chs.txt。
	dictionary = csv.DictReader(open("./Build/DerivedData/tsi-chs.csv"), delimiter='\t')
	print ("正在生成 macOS 版威注音與小麥注音專用的 data-chs.txt")
	try:
		handle = open('data-chs.txt', "w")
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
