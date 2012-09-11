#!/bin/bash

# Copyright 2010 Gavin Wood.
# This file may be distributed according to the GNU GPL version 3.
# The GNU GPL version 3 is defined at http://www.gnu.org/licenses/gpl-3.0.html

source="/media/FLAC/FLAC"
dest="/media/FLAC/MP3"

cd $source

printf "Searching..."
find . -name \*.flac | while read s
do
	if [[ ! -e "$dest/${s/%.flac/.mp3}" ]]
	then
		export total=$(($total + 1))
	fi
	echo $total > /tmp/.sync-total-$$
done

total=`cat /tmp/.sync-total-$$`
rm -f /tmp/.sync-total-$$

shopt -s extglob

i=1
find . -name \*.flac | while read s
do
	d=$dest/${s/%.flac/.mp3}
	mkdir -p "${d%/*}"
	if [[ ! -e "$d" ]]
	then
		printf "\rEncoding: %6s/$total" $i
		nice -n 19 gst-launch filesrc location="$s" ! flacdec ! lame preset=medium ! id3v2mux ! filesink location="$dest/.incoming" >/tmp/.sync-out-$$ 2>/dev/null
		[[ `grep Interrupt /tmp/.sync-out-$$` ]] && exit
		rm -f /tmp/.sync-out-$$
		mv "$dest/.incoming" "$d"
		i=$(($i + 1))
	fi
	if [[ ! -e "${d%/*}/cover.jpg" && -e "${s%/*}/cover.jpg" ]]
	then
		cp "${s%/*}/cover.jpg" "${d%/*}"
	fi
done

echo ""
echo "Done."

