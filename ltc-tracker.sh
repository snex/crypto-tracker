#!/bin/bash

usage() {
	cat << EOF
Usage: $0 -t <target> [-hbcgmpvHPU]
Hunt for a Litecoin block hash / transaction / address based on a partial match

-h, -help,		--help		Display help

-b, -ltc-bin,		--ltc-bin	Path to bitcoin-cli
					Default will look in PATH

-c, -conf,		--conf		Path to bitcoin.conf, if necessary
					Default is blank

-g, -height,		--height	Height to start searching from
					Searches go from <height> down to 1
					Defaults to the current height

-m, -match-type,	--match-type	Type of match to look for
					Possible values are "any", "start", "end"
					Default is "any"

-p, -type,		--type		The type of target to hunt for
					Possible values are "hash", "txid", "address"
					Default is "hash"

-t, -target,		--target	The target string to hunt for, required

-v, -verbose,		--verbose	Enable verbose mode

-H, -host,		--host		Host for Litecoin RPC daemon
					Default is 127.0.0.1

-P, -port,		--port		Port for Litecoin RPC daemon
					Default is 9332

-U, -user,		--user		RPC username
					If present, password will be prompted for
					Do not use combined with --cookie
EOF
exit 0
}

checkType() {
	if [[ "$targettype" =~ ^(hash|txid|address)$ ]]; then
		return 0
	else
		echo 'Type must be "hash", "txid", or "address".'
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

passwordPrompt() {
	read -s -p "RPC Password: " rpcpass
	echo ""
}

logger() {
	if [[ $verbose -eq 1 ]]; then
		echo $1
	fi
}

export ltcbin=`which litecoin-cli`
export ltcconf=""
export height=""
export matchtype="any"
export targettype="hash"
export verbose=0
export rpchost="127.0.0.1"
export rpcport="9332"
export rpcuser=""
export rpcpass=""
export ltcopts=""


[ $# -eq 0 ] && usage
options=$(getopt -l "help,ltc-bin::,conf::,height::,match-type::,type::,target:,verbose,host::,port::,user::" -o "hb::c::g::m::p::t:vH::P::U::" -a -- "$@")

eval set -- "$options"

while true
do
	case "$1" in
		-h|--help)
			usage ;;
		-b|--ltc-bin)
			shift ; export ltcbin="$1" ;;
		-c|--conf)
			shift ; export ltcconf="$1" ;;
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
		-U|--user)
			shift ; export rpcuser="$1" ;;
		--)
			shift ; break ;;
	esac
	shift
done

if [ -z "$target" ]; then
	echo "Error: -t|--target option is mandatory." >&2
	exit 1
fi

if [ -n "$ltcconf" ]; then
	export ltcopts=" -conf=$ltcconf"
fi

if [ -n "$rpchost" ]; then
	export ltcopts="$ltcopts -rpcconnect=$rpchost"
fi

if [ -n "$rpcport" ]; then
	export ltcopts="$ltcopts -rpcport=$rpcport"
fi

if [ -n "$rpcuser" ]; then
	export ltcopts="$ltcopts -rpcuser=$rpcuser"
	passwordPrompt
fi

if [ -n "$rpcpass" ]; then
	export ltcopts="$ltcopts -rpcpassword=$rpcpass"
fi

export ltccmd="$ltcbin $ltcopts"

if [ -z "$height" ]; then
	export height=`$ltccmd getblockchaininfo | jq ".blocks"`
fi

for ((i=$height; i>=1; i--)); do
	BLKHSH=`$ltccmd getblockhash $i`

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
		TXIDS=`$ltccmd getblock $BLKHSH | jq -r ".tx[]"`

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
	elif [[ $targettype == "address" ]]; then
		TXIDS=`$ltccmd getblock $BLKHSH | jq -r ".tx[]"`

		for TXID in $TXIDS; do
			logger "-- Checking txid $TXID at height $i"
			ADDYS=`$ltccmd getrawtransaction $TXID true $BLKHSH | jq -r ".vout | map({scriptPubKey})[].scriptPubKey.addresses | select( . != null )[]"`

			for ADDY in $ADDYS; do
				logger "---- Checking address $ADDY"

				case $matchtype in
					any)
						match=$([[ $ADDY == *"$target"* ]] && echo 1 || echo 0) ;;
					start)
						match=$([[ $ADDY == "$target"* ]] && echo 1 || echo 0) ;;
					end)
						match=$([[ $ADDY == *"$target" ]] && echo 1 || echo 0) ;;
				esac
				if [[ $match -eq 1 ]]; then
					echo "Found address matching $target at height $i in transaction ID $TXID!"
					exit 0
				fi
			done
		done
	fi
done
