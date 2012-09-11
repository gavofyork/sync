#!/bin/bash

# Copyright 2010 Gavin Wood.
# This file may be distributed according to the GNU GPL version 3.
# The GNU GPL version 3 is defined at http://www.gnu.org/licenses/gpl-3.0.html

function VERSION ()
{
    echo ${0/*\/}
    echo "Version 1.0, Copyright Gavin Wood, 2010."
    echo ""
    echo "${0/*\/} is Free Software. It is licenced under the GNU General"
    echo "Public Licence version 3. See http://www.gnu.org/licences for"
    echo "more information."
}

function USAGE ()
{
    echo ""
    echo "USAGE: "
    echo "    ${0/*\/} <path>"
    echo ""
    echo "OPTIONS:"
    echo "    <path>         Specify path for files"
    echo "    -h             This usage information"
    echo "    -v             Version information"
    echo ""
    echo "EXAMPLE:"
    echo "    ${0/*\/} /media/M4A"
    echo ""
    exit $E_OPTERROR    # Exit and explain usage, if no argument(s) given.
}

while getopts "hv" Option
do
    case $Option in
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
path="$1"
opath="${0%\/*}"
opwd="$PWD"
echo $0 $opath
cp setComp.py getArt.py /tmp

[[ -z "$path" ]] && USAGE

filter=".*(m4a)"

declare -a sources

cd "$path"
printf "Searching...\r"

declare -a paths

# paths that are definitely various artists
declare -A varpaths

last=""
count=0
artist=""
various=1

while read s
do
	COLUMNS=`tput cols`
	sources[${#sources[@]}]="$s"
	nnfw=$((11 + 7 + 2))
	nfw=$(( (COLUMNS > nnfw) ? COLUMNS - nnfw : 0))
	printf "Searching: %7s: %-${nfw}.${nfw}s\r" ${#sources[@]} "$s"
	
	path="${s%/*}"
	npaths=${#paths[@]}
	if [[ $npaths -lt 1 ]] || [[ "${paths[$(( npaths - 1 )) ]}" != "$path" ]]
	then
		a=$(/tmp/getArt.py "$s")
		paths[$npaths]="$path"
		last="$s"
		count=0
		artist="$a"
		various=0
	elif [[ $various == 0 ]]
	then
		a=$(/tmp/getArt.py "$s")
		if [[ "$artist" != "$a" ]]
		then
			various=1
			varpaths["$path"]=1
		fi
	fi
	(( count++ ))
done < <( find . -regextype posix-extended -iregex "$filter" )

shopt -s extglob

total=${#sources[@]}
incoming=""
s=""
d=""
dotd=""
i=0
while [[ 1 ]]
do
	for (( ; i < total; i++ ))
	do
		s="${sources[$i]}"
		path="${s%/*}"
		if [[ ${varpaths[$path]} ]]
		then
			/tmp/setComp.py "$s"
		fi
	done
	(( i >= total )) && break
done

echo
echo "Done."

