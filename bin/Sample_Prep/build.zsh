#!/bin/zsh
# Mengjuei Hsieh, OpenVanilla
scriptPATH=`cd $(dirname $0) && pwd`
. ${scriptPATH}/filter.zsh
find * -type f -print \
    | grep -iv -e zsh -e DS_S -e README \
               -e AcademiaSinicaBakeoff2005.lm \
    | xargs cat \
    | OVTrainingSetFilter \
    | perl ${scriptPATH}/../nonCJK_filter.pl \
    | perl -pe 's/(.{0,80})\s/$1\n/g' \
    | env LC_ALL=zh_TW.UTF8 sort -u
