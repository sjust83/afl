#!/bin/bash
#
# american fuzzy lop - path minimization tool
# -------------------------------------------
#
# Written and maintained by Michal Zalewski <lcamtuf@google.com>
#
# Copyright 2014 Google Inc. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at:
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# This tool tries to find a subset of discovered paths that includes all tuple
# values seen so far. This subset is usually considerably smaller than the
# raw, progressively generated queue/ directory created by the fuzzer, because
# many test cases are rendered obsolete by later finds with better coverage.
#
# Note that the tool assumes that the tested program reads from stdin and
# requires no cmdline parameters; very simple edits are required to support 
# other use cases.
#

echo "path minimization tool for afl-fuzz by <lcamtuf@google.com>"
echo

ulimit -v 100000

if [ ! "$#" = "2" ]; then
  echo "Usage: $0 /path/to/testcases_dir /path/to/tested_binary" 1>&2
  echo 1>&2
  echo "Note: the tested binary must accept input on stdin and require no additional"1>&2
  echo "parameters. For more complex use cases, you need to edit this script." 1>&2
  echo 1>&2
  exit 1
fi

DIR="$1"
BIN="$2"

if [ ! -f "$BIN" -o ! -x "$BIN" ]; then
  echo "Error: binary '$2' not found or is not executable." 1>&2
  exit 1
fi

if [ ! -d "$DIR" ]; then
  echo "Error: directory '$1' not found." 1>&2
  exit 1
fi

test "$AFL_PATH" = "" && AFL_PATH=/usr/local/bin

SM="$AFL_PATH/afl-showmap"

if [ ! -x "$SM" ]; then
  echo "Can't find $SM - please set AFL_PATH."
  exit 1
fi

CCOUNT=`ls -- "$DIR" 2>/dev/null | wc -l`

if [ "$CCOUNT" = "0" ]; then
  echo "No inputs in the target directory - nothing to be done."
  exit 0
fi

rm -rf .traces 2>/dev/null
mkdir .traces || exit 1

OUT_DIR="$DIR.minimized"

rm -rf -- "$OUT_DIR" 2>/dev/null
mkdir "$OUT_DIR" || exit 1

echo "[*] Evaluating input files (this may take a while)..."

for c in $DIR/*; do

  B=`basename -- "$c"`

  # Modify this if $BIN needs to be called with additional parameters, etc.

  AFL_SINK_OUTPUT=1 "$SM" "$BIN" <"$c" 2>&1 | grep -E '^[0-9]{5}/[0-9]{1,3}$' >".traces/$B"

  TC=`grep -c . ".traces/$B"`

  cat ".traces/$B" >>.traces/.all

  awk '{print "'$TC'~" $0 "~'"$B"'"}' <".traces/$B" >>.traces/.lookup

done

sort .traces/.all | uniq -c | sort -n >.traces/.all_uniq

sort -rn .traces/.lookup >.traces/.lookup_sorted

TCOUNT=`grep -c . .traces/.all_uniq`

echo "[+] Found $TCOUNT unique tuples across $CCOUNT files."
echo "[*] Minimizing..."

touch .traces/.already_have

while read -r cnt tuple; do

  # If we already have this tuple, skip it.

  grep -q "^$tuple\$" .traces/.already_have && continue

  # Find the best candidate for this tuple.

  FN=`grep "~$tuple~" .traces/.lookup_sorted | head -1 | cut -d~ -f3-`

  cat "$DIR/$FN" >"$OUT_DIR/$FN"
  cat ".traces/$FN" >>.traces/.already_have

done <.traces/.all_uniq

NCOUNT=`ls -- "$OUT_DIR" | wc -l`

echo "[+] Narrowed down to $NCOUNT files, saved in '$OUT_DIR'."

rm -rf .traces
