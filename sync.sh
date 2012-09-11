#!/bin/bash

# Copyright 2010 Gavin Wood.
# This file may be distributed according to the GNU GPL version 3.
# The GNU GPL version 3 is defined at http://www.gnu.org/licenses/gpl-3.0.html

mp3stream="lame preset=medium"
aacstream="faac profile=2 ! ffmux_mp4"
stream=""
extension=""

function VERSION ()
{
    echo ${0/*\/}
    echo "Version 2.0, Copyright Gavin Wood, 2010."
    echo ""
    echo "${0/*\/} is Free Software. It is licenced under the GNU General"
    echo "Public Licence version 3. See http://www.gnu.org/licences for"
    echo "more information."
}

function USAGE ()
{
    echo ""
    echo "USAGE: "
    echo "    ${0/*\/} [-s|-x] <from> <to>"
    echo ""
    echo "OPTIONS:"
    echo "    -s <stream>    Specify custom gstreamer pipeline"
    echo "    -x <extension> Specify filename extension (default mp3)"
    echo "    <from>         Specify source path for files"
    echo "    <to>           Specify destination path for files"
    echo "    -h             This usage information"
    echo "    -v             Version information"
    echo ""
    echo "EXAMPLE:"
    echo "    ${0/*\/} /media/FLACs /media/MP3s"
    echo ""
    exit $E_OPTERROR    # Exit and explain usage, if no argument(s) given.
}

while getopts ":s:x:h:v" Option
do
    case $Option in
        x    ) extension="$OPTARG";;
        s    ) stream="$OPTARG";;
        v    ) VERSION
               exit 0;;
        h    ) USAGE
               exit 0;;
        *    ) echo ""
               echo "Unimplemented option chosen."
               USAGE   # DEFAULT
    esac
done

shift $(($OPTIND - 1))
source="$1"
dest="$2"

if [[ "x$source" == "x" ]]; then USAGE; fi
if [[ "x$dest" == "x" ]]; then USAGE; fi

if [[ "x$extension" == "x" ]]; then
	extension=mp3
fi

if [[ "x$stream" == "x" ]]; then
	if [[ "$extension" == "m4a" || "$extension" == "aac" ]]; then
		stream="$aacstream"
	else
		stream="$mp3stream"
	fi
fi

filter=".*(flac|mp3|aac|m4a|mp2|ogg|vorbis|wav|mkv)"

declare -a sources

cd $source
printf "Searching..."
while read s
do
	if [[ ! -e "$dest/${s%.*}.$extension" ]]
	then
		sources[${#sources[@]}]="$s"
	fi
done < <( find . -regextype posix-extended -iregex "$filter" )


shopt -s extglob

total=${#sources[@]}
for (( i = 0 ; i < total ; i++ ))
do
	s="${sources[$i]}"
	d="$dest/${s%.*}.$extension"
	mkdir -p "${d%/*}"
	printf "\rEncoding: %6s/$total" $i
	nice -n 19 gst-launch filesrc "location=$s" ! decodebin ! $stream ! id3v2mux ! filesink "location=$dest/.incoming" >/tmp/.sync-out-$$ 2>/dev/null
	
	[[ `grep Interrupt /tmp/.sync-out-$$` ]] && { echo "Interrupted."; exit; }
	
	rm -f /tmp/.sync-out-$$
	mv "$dest/.incoming" "$d"
	
	if [[ ! -e "${d%/*}/cover.jpg" && -e "${s%/*}/cover.jpg" ]]
	then
		cp "${s%/*}/cover.jpg" "${d%/*}"
	fi
done

echo ""
echo "Done."

