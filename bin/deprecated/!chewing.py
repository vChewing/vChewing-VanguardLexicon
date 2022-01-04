#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import sys
import csv
import math
import itertools
__author__ = 'Programmed by Shiki Suen. (formulas by MJHsieh.)'

mydict = {}
norm	  = 0.0
fscale	= 2.7

if __name__ == '__main__':
	# 第一次讀取「tsi.csv」，主要用來統計 norm 數據。
	# norm 數據的統計公式著作權歸 MJHsieh 所有。
	lines = csv.DictReader(open("tsi.csv"), delimiter='\t')
	for entry in lines:
		norm += fscale**(len(entry['kanji'])/3-1)*float(entry['count'])
	# 第二次讀取「tsi.csv」，生成辭典。
	dictionary = csv.DictReader(open("tsi.csv"), delimiter='\t')
	try:
		handle = open('data.txt', "w")
	except IOError as e:
		print(("({})".format(e)))
	for entry in dictionary:
		# 將新酷音的詞語出現次數數據轉換成小麥引擎可讀的數據形式。
		# 對出現次數小於 1 的詞條，將 0 當成 0.5 來處理、以防止除零。
		# 統計公式著作權歸 MJHsieh 所有。
		if float(entry['count']) < 1:
			entry['freq'] = math.log(fscale**(len(entry['kanji'])/3-1)*0.5/norm, 10)
		else:
			entry['freq'] = math.log(fscale**(len(entry['kanji'])/3-1)*float(entry['count'])/norm, 10)
		# print(entry)
		handle.write('%s %s %s\n' % (entry['kanji'], entry['bpmf'], entry['freq']))
	handle.close()
