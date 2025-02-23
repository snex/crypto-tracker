#!/bin/bash

usage() {
	cat << EOF
Usage: $0 -t <target> [-hgmpvHP]
Hunt for a Monero block hash / transaction based on a partial match

-h, -help,		--help		Display help


-g, -height,		--height	Height to start searching from
					Searches go from <height> down to 1
					Defaults to the current height

-m, -match-type,	--match-type	Type of match to look for
					Possible values are "any", "start", "end"
					Default is "any"

-p, -type,		--type		The type of target to hunt for
					Possible values are "hash", "txid"
					Default is "hash"

-t, -target,		--target	The target string to hunt for, required

-v, -verbose,		--verbose	Enable verbose mode

-H, -host,		--host		Host for Monero daemon
					Default is 127.0.0.1

-P, -port,		--port		Port for Monero daemon
					Default is 18081
EOF
exit 0
}

checkType() {
	if [[ "$targettype" =~ ^(hash|txid)$ ]]; then
		return 0
	else
		echo 'Type must be "hash", or "txid".'
		exit 1
	fi
}

checkMatchType() {
	if [[ "$matchtype" =~ ^(any|start|end)$ ]]; then
		return 0
	else
		echo 'Match Type must be "any", "start", or "end".'
		exit 1
	fi
}

logger() {
	if [[ $verbose -eq 1 ]]; then
		echo $1
	fi
}

export height=""
export matchtype="any"
export targettype="hash"
export verbose=0
export rpchost="127.0.0.1"
export rpcport="18081"

[ $# -eq 0 ] && usage
options=$(getopt -l "help,height::,match-type::,type::,target:,verbose,host::,port::" -o "hg::m::p::t:vH::P::" -a -- "$@")

eval set -- "$options"

while true
do
	case "$1" in
		-h|--help)
			usage ;;
		-g|--height)
			shift ; export height="$1" ;;
		-m|--match-type)
			shift ; export matchtype="$1"
			checkMatchType
			;;
		-p|--type)
			shift ; export targettype="$1"
			checkType
			;;
		-t|--target)
			shift ; export target="$1" ;;
		-v|--verbose)
			export verbose=1 ;;
		-H|--host)
			shift ; export rpchost="$1" ;;
		-P|--port)
			shift ; export rpcport="$1" ;;
		--)
			shift ; break ;;
	esac
	shift
done

if [ -z "$target" ]; then
	echo "Error: -t|--target option is mandatory." >&2
	exit 1
fi

export xmropts="-s -X POST http://$rpchost:$rpcport/json_rpc -H 'Content-Type: application/json'"

if [ -z "$height" ]; then
	export height=$(curl $xmropts -d '{"jsonrpc":"2.0","id":"0","method":"get_info"}' | jq -r ".result.height")
fi

for ((i=$height-1; i>=1; i--)); do
	BLKHSH=$(curl $xmropts -d '{"jsonrpc":"2.0","id":"0","method":"get_block_header_by_height","params":{"height":'$i'}}' | jq -r ".result.block_header.hash")
	echo $BLKHSH

	logger "Checking blockhash $BLKHSH at height $i"

	if [[ $targettype == "hash" ]]; then
		case $matchtype in
			any)
				match=$([[ $BLKHSH == *"$target"* ]] && echo 1 || echo 0) ;;
			start)
				match=$([[ $BLKHSH == "$target"* ]] && echo 1 || echo 0) ;;
			end)
				match=$([[ $BLKHSH == *"$target" ]] && echo 1 || echo 0) ;;
		esac
		if [[ $match -eq 1 ]]; then
			echo "Found blockhash matching $target at height $i!"
			echo "$BLKHSH"
			exit 0
		fi
	elif [[ $targettype == "txid" ]]; then
		TXIDS=$(curl $xmropts -d '{"jsonrpc":"2.0","id":"0","method":"get_block","params":{"height":'$i'}}' | jq -r ".result.tx_hashes[]")

		for TXID in $TXIDS; do
			logger "-- Checking txid $TXID at height $i"

			case $matchtype in
				any)
					match=$([[ $TXID == *"$target"* ]] && echo 1 || echo 0) ;;
				start)
					match=$([[ $TXID == "$target"* ]] && echo 1 || echo 0) ;;
				end)
					match=$([[ $TXID == *"$target" ]] && echo 1 || echo 0) ;;
			esac

			if [[ $match -eq 1 ]]; then
				echo "Found transaction ID matching $target at height $i!"
				echo "$TXID"
				exit 0
			fi
		done
	fi
done
