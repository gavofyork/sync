#!/bin/bash

# Copyright 2010 Gavin Wood.
# This file may be distributed according to the GNU GPL version 3.
# The GNU GPL version 3 is defined at http://www.gnu.org/licenses/gpl-3.0.html

mp3stream="lame preset=medium"
aacstream="faac bitrate=64000 ! ffmux_mp4"
usenero=""
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
    echo "    ${0/*\/} [-n|-s|-x] <from> <to>"
    echo ""
    echo "OPTIONS:"
    echo "    -s <stream>    Specify custom gstreamer pipeline"
    echo "    -x <extension> Specify filename extension (default mp3)"
    echo "    -n             Use the Nero HE-AAC encoder (requires FLAC inputs for now)"
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

while getopts "ns:x:hv" Option
do
    case $Option in
        n    ) usenero=1;;
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

[[ -z "$source" ]] && USAGE
[[ -z "$dest" ]] && USAGE

if [[ -z "$extension" ]]; then
	if [[ -n "$usenero" ]]; then
		extension=mp4
	else
		extension=mp3
	fi
fi

if [[ -z "$stream" ]]; then
	if [[ "$extension" == "m4a" ]] || [[ "$extension" == "aac" ]]; then
		stream="$aacstream"
	else
		stream="$mp3stream"
	fi
fi

filter=".*(flac|mp3|aac|m4a|mp2|ogg|vorbis|wav|mkv)"

declare -a sources
havePid () { ps ax -o pid --no-heading | grep "^ *$1\$" >/dev/null; }

ndd=""
dotndd=""

#Returns value into ndd/dotndd.
needsDoing () {
	ndd="$dest/${1%.*}.$extension"
	if [[ -e "$ndd" ]]
	then
		# Already converted.
		ndd=""
	else
		dotndd="$dest/${1%.*}.$extension~"
		# Not yet converted.
		if [[ -e "$dotndd" ]] && havePid `cat "$dotndd"`
		then
			# Current process is converting it. Leave well alone.
			ndd=""
			dotndd=""
		else
			# Not started or old process was converting but interrupted.
			rm -f "$dotndd" 2> /dev/null
		fi
	fi
}


lockfile="$dest/.lock"
function lock ()
{
	while [[ 1 ]]
	do
		echo $$ > "$lockfile"
		chmod -w "$lockfile"
		lfc=`cat "$lockfile"`
		[[ $$ == $lfc ]] && break
		if ! havePid $lfc 
		then
			rm -f "$lockfile"
		else
			sleep 0.01
		fi
	done
}

function unlock ()
{
	rm -f "$lockfile"
}

cd $source
printf "Searching..."

lock 2> /dev/null
while read s
do
	needsDoing "$s"
	if [[ -n "$ndd" ]]
	then
		sources[${#sources[@]}]="$s"
		printf "\rSearching: %7s: %-55.55s" ${#sources[@]} "$s"
	fi
done < <( find . -regextype posix-extended -iregex "$filter" )
unlock

shopt -s extglob

total=${#sources[@]}
incoming=""
s=""
d=""
dotd=""
i=0
while [[ 1 ]]
do
	[[ -n "$incoming" ]] && [[ -n "$d" ]] && mv "$incoming" "$d"
	
# START CRITICAL
	lock 2>/dev/null

	[[ -n "$dotd" ]] && rm -f "$dotd"
	
	for (( ; i < total; i++ ))
	do
		s="${sources[$i]}"
		needsDoing "$s"
		d="$ndd"
		dotd="$dotndd"
		
		if [[ -n "$d" ]]
		then
			mkdir -p "${d%/*}"
			echo $$ > "$dotd"
			break
		fi
	done
	
	unlock 2>/dev/null
# END CRITICAL

	(( i >= total )) && break

	printf "\rEncoding: %${#total}s/$total: %-55.55s" $i "$s"
	if [[ -n "$usenero" ]]
	then
		incoming="$dest/.incoming-$$.mp4"
		mknod "/tmp/p-$$" p
		nice -n 19 gst-launch filesrc "location=$s" ! decodebin ! wavenc ! filesink "location=/tmp/p-$$" 1>/dev/null 2>/dev/null &
		nice -n 19 neroAacEnc -q 0.15 -if "/tmp/p-$$" -of "$incoming" 1>/dev/null 2>/tmp/.sync-out-$$ && 
		nice -n 19 metaflac --export-tags-to=- "$s" | while read tag
		do
			echo -n -
			printf "meta-user:%s\0" "$tag"
			n="${m/=*}"
			v="${m/*=}"
# Fix-ups for iTunes. UNTESTED
			[[ "$n" == "compilation" ]] && echo -n - && printf "meta-user:itunescompilation=%s\0" "$v"
			[[ "$n" == "tracktotal" ]] && echo -n - && printf "meta-user:totaltracks=%s\0" "$v"
			[[ "$n" == "disctotal" ]] && echo -n - && printf "meta-user:totaldiscs=%s\0" "$v"
		done | xargs -0 neroAacTag "$incoming" 1>/dev/null 2>/dev/null
		rm -f "/tmp/p-$$"
	else
		incoming="$dest/.incoming-$$"
		nice -n 19 gst-launch filesrc "location=$s" ! decodebin ! $stream ! id3v2mux ! filesink "location=$incoming" >/tmp/.sync-out-$$ 2>/dev/null
	fi
	
	if [[ `grep Interrupt /tmp/.sync-out-$$` ]]
	then
		echo ""
		echo "Interrupted."
		rm -f /tmp/.sync-out-$$
		rm -f "$incoming"
		rm -f "$dotd"
		exit
	fi
	
	rm -f /tmp/.sync-out-$$
	
	[[ ! -e "${d%/*}/cover.jpg" ]] && [[ -e "${s%/*}/cover.jpg" ]] && cp "${s%/*}/cover.jpg" "${d%/*}"

	(( i++ ))
done

echo ""
echo "Done."

