#!/usr/bin/env sh

# Make it look pretty
bold=$(tput bold)
normal=$(tput sgr0)

# fast-forward merges, as the name implied, just tack on successive commits onto
# master so it's really hard to figure out which commits were introduced by a
# fast-forward merge

#LAST_MERGE=$(git --no-pager log staging master --oneline --merges -2)
#echo Last merge commit between staging and master was $bold$LAST_MERGE$normal

# LAST_MERGE_HASH=$(git --no-pager log staging master --oneline --merges -1 --pretty="format:%H")
# Formats merge commits into a bullet list
git --no-pager log origin/master..staging --pretty="format:- %s %n%w(0,4,4)%b" --first-parent
