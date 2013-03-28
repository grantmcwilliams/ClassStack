#!/bin/bash

SCRIPTDIR=$(dirname $(readlink -f "${BASH_SOURCE[0]}"))
source "$SCRIPTDIR/xaptools.lib" 

IBCFILE="$1"
if [ -z "$IBCFILE" ] ;then
	echo "No rosterfile specified - exiting"
	exit 1
fi

if [ -d /root/bin/Rosters ] ;then
	ROSTDIR="$SCRIPTDIR/Rosters"
else
	mkdir -p "$SCRIPTDIR/Rosters"
	ROSTDIR="$SCRIPTDIR/Rosters"
fi

NEWROSTER="$ROSTDIR/ROSTDOWN.csv"
if [ -e "$NEWROSTER" ];then
	if ! yesno "Roster already exits - append? y|n" ;then
		rm "$NEWROSTER"
	fi 
fi

IFS=$'\n'
COURSE=$(grep -A1 QUARTER ${IBCFILE} | tail -n1 | awk -F'\t' '{print $3}')
for LINE in $(cat $IBCFILE) ;do
	if echo $LINE | grep -q '^[0-9]' ;then
		NEWLINE=$(echo "$LINE" | sed 's/\t/,/g' | awk -F, '{print $2","$3","$5","$6","$7}')
		echo "${COURSE},${NEWLINE}" >> "$NEWROSTER"
	fi
done

if [[ -e $NEWROSTER ]] ;then	
	dos2unix "$NEWROSTER" &> /dev/null
fi
