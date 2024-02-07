#!/usr/bin/env bash



# ensure paths are correct irrespective from where user runs the script
scriptdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
maindir="$(dirname "$scriptdir")"

for sub in `cat $scriptdir/sublist_all.txt`; do

	SCRIPTNAME=${scriptdir}/preprocess.sh
	NCORES=25
	while [ $(ps -ef | grep -v grep | grep $SCRIPTNAME | wc -l) -ge $NCORES ]; do
			sleep 5s
	done
	bash $SCRIPTNAME $sub &
	sleep 1s

done
