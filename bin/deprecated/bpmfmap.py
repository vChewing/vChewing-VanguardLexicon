#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# A really lame bpmf mapping
import sys

__author__ = 'Mengjuei Hsieh'

bpmf = {}

if __name__ == '__main__':
    try:
        handle = open('heterophony1.list', "r")
    except IOError as e:
        print(("({})".format(e)))
    while True:
        line = handle.readline()
        if not line: break
        if line[0] == '#': continue
        elements = line.rstrip().split()
        if elements[0] in bpmf:
            pass
        else:
            bpmf[elements[0]] = elements[1]
    handle.close()
    try:
        handle = open('BPMFBase.txt', "r")
    except IOError as e:
        print(("({})".format(e)))
    while True:
        line = handle.readline()
        if not line: break
        if line[0] == '#': continue
        elements = line.rstrip().split()
        if elements[0] in bpmf:
            pass
        else:
            bpmf[elements[0]] = elements[1]
    handle.close()
    try:
        handle = open('cand.occ', "r")
    except IOError as e:
        print(("({})".format(e)))
    while True:
        line = handle.readline()
        if not line: break
        if line[0] == '#': continue
        elements = line.rstrip().split()
        word = elements[0]
        i = 0
        phon = word
        while i < len(word):
            phon = "%s %s" % (phon, bpmf["%s%s%s" % (word[i], word[i+1], word[i+2])])
            i = i+3
        print(phon)
    handle.close()
