#!/bin/bash

# Copyright 2010 Gavin Wood.
# This file may be distributed according to the GNU GPL version 3.
# The GNU GPL version 3 is defined at http://www.gnu.org/licenses/gpl-3.0.html

mp3stream="lame preset=medium"
aacstream="faac bitrate=64000 ! ffmux_mp4"
oggstream="vorbisenc quality=2 ! oggmux"
usenero=""
useoggenc=""
stream=""
extension=""
albumart=""

function VERSION ()
{
    echo ${0/*\/}
    echo "Version 4.0, Copyright Gavin Wood, 2012."
    echo ""
    echo "${0/*\/} is Free Software. It is licenced under the GNU General"
    echo "Public Licence version 3. See http://www.gnu.org/licences for"
    echo "more information."
}

function USAGE ()
{
    echo ""
    echo "USAGE: "
    echo "    ${0/*\/} [-n|-o|-s|-x|-a] <from> <to>"
    echo ""
    echo "OPTIONS:"
    echo "    -s <stream>    Specify custom gstreamer pipeline"
    echo "    -x <extension> Specify filename extension (default mp3)"
    echo "    -n             Use the Nero HE-AAC encoder (requires FLAC inputs for now)"
    echo "    -o <quality>   Use the OggEnc encoder at given quality"
    echo "    -a <filename>  Specify album art filename (default cover.jpg)"
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

while getopts "no:s:a:x:hv" Option
do
    case $Option in
        n    ) usenero=1;;
        o    ) useoggenc="$OPTARG";;
        a    ) albumart="$OPTARG";;
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
	elif [[ -n "$useoggenc" ]]; then
		extension=ogg
	else
		extension=mp3
	fi
fi

if [[ -z "$stream" ]]; then
	if [[ "$extension" == "m4a" ]] || [[ "$extension" == "aac" ]]; then
		stream="$aacstream"
	elif [[ "$extension" == "ogg" ]] || [[ "$extension" == "vorbis" ]]; then
		stream="$oggstream"
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
mkdir -p "$dest"
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
printf "Searching...\r"

declare -a wrongcount;
declare -a missingart;
declare -a paths;

last="";
count=0;

lock 2> /dev/null
while read s
do
	COLUMNS=`tput cols`
	needsDoing "$s"
	if [[ -n "$ndd" ]]
	then
		sources[${#sources[@]}]="$s"
		nnfw=$((11 + 7 + 2))
		nfw=$(( (COLUMNS > nnfw) ? COLUMNS - nnfw : 0))
		printf "Searching: %7s: %-${nfw}.${nfw}s\r" ${#sources[@]} "$s"
	fi
	
	path="${s%/*}"
	npaths=${#paths[@]}
	if [[ $npaths -lt 1 ]] || [[ "${paths[$(( npaths - 1 )) ]}" != "$path" ]]
	then
		if [[ $count -gt 0 && $(metaflac --export-tags-to=- "$last" | grep TRACKTOTAL | cut -d= -f2) -ne $count ]]
		then
			wrongcount[${#wrongcount[@]}]="${last%/*}"
		fi

		paths[$npaths]="$path"
		last="$s"
		count=0
		
		if [[ -n "$albumart" ]] && [[ ! -e "$path/$albumart" ]]
		then
			missingart[${#missingart[@]}]="$path"
		fi
	fi
	(( count++ ))
done < <( find . -regextype posix-extended -iregex "$filter" )
unlock

if [[ ${#wrongcount[@]} -gt 0 ]]
then
	printf "\nMissing track(s) in:\n"
	for m in "${wrongcount[@]}"
	do
		printf "%-*.*s\n" $((COLUMNS)) $((COLUMNS)) "$m"
	done
fi

if [[ ${#missingart[@]} -gt 0 ]]
then
	printf "\nMissing album art in:%-*.*s\n" $((COLUMNS - 22)) $((COLUMNS - 22)) ""
	for m in "${missingart[@]}"
	do
		printf "%-*.*s\n" $((COLUMNS)) $((COLUMNS)) "$m"
		q="${m/*\/}" && q="${q/ \[?-?]}" && q="${q/ \[-]}"
		[[ -x ~/getalbumart.php ]] && ~/getalbumart.php -q -r "${q/ - *}" -l "${q/* - }" -p "$m" -n ".x" && mv "$m"/.x.* "$m/$albumart"
	done
fi

shopt -s extglob

total=${#sources[@]}
incoming=""
s=""
d=""
dotd=""
i=0
while [[ 1 ]]
do
	if [[ -n "$incoming" ]] && [[ -n "$d" ]]
	then
		if [[ -e "$incoming" ]]
		then
			mv "$incoming" "$d"
		else
			echo "***ERROR"
		fi
	fi
	
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

	COLUMNS=`tput cols`
	nnfw=$((10 + 2 * ${#total} + 1 + 2))
	nfw=$(( (COLUMNS > nnfw) ? COLUMNS - nnfw : 0))
	printf "Encoding: %${#total}s/$total: %-*.*s\r" $i $nfw $nfw "$s"
	if [[ -n "$usenero" ]]
	then
		incoming="$dest/.incoming-$$.mp4"
		mknod "/tmp/p-$$" p
		nice -n 19 gst-launch filesrc "location=$s" ! decodebin ! audioconvert ! wavenc ! filesink "location=/tmp/p-$$" 1>/dev/null 2>/dev/null &
		nice -n 19 neroAacEnc -q 0.3 -if "/tmp/p-$$" -of "$incoming" 1>/dev/null 2>/tmp/.sync-out-$$;
		if [[ -e "$incoming" ]] ; then
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
		else
			echo "PROBLEM:  "
		fi
		rm -f "/tmp/p-$$"
	elif [[ -n "$useoggenc" ]]
	then
		incoming="$dest/.incoming-$$"	
		nice -n 19 oggenc "$s" -o "$incoming" -q $useoggenc >/tmp/.sync-out-$$ 2>/dev/null
	else
		incoming="$dest/.incoming-$$"
		nice -n 19 gst-launch filesrc "location=$s" ! decodebin ! audioconvert ! $stream ! id3v2mux ! filesink "location=$incoming" >/tmp/.sync-out-$$ 2>/dev/null
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
	
	[[ ! -e "${d%/*}/$albumart" ]] && [[ -e "${s%/*}/$albumart" ]] && cp "${s%/*}/$albumart" "${d%/*}"

	(( i++ ))
done

echo ""
echo "Done."

