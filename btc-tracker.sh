#!/bin/bash

usage() {
	cat << EOF
Usage: $0 -t <target> [-hbcgmpvCHPU]
Hunt for a Bitcoin block hash / transaction / address based on a partial match

-h, -help,		--help		Display help

-b, -btc-bin,		--btc-bin	Path to bitcoin-cli
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

-C, -cookie,		--cookie	RPC auth cookie
					Do not use combined with --user

-H, -host,		--host		Host for Bitcoin RPC daemon
					Default is 127.0.0.1

-P, -port,		--port		Port for Bitcoin RPC daemon
					Default is 8332

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

checkUserAndCookie() {
	if [[ -n "$rpccookie" && -n "$rpcuser" ]]; then
		echo "Error: Both --cookie and --user cannot be present." >&2
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

export btcbin=`which bitcoin-cli`
export btcconf=""
export height=""
export matchtype="any"
export targettype="hash"
export verbose=0
export rpccookie=""
export rpchost="127.0.0.1"
export rpcport="8332"
export rpcuser=""
export rpcpass=""
export btcopts=""


[ $# -eq 0 ] && usage
options=$(getopt -l "help,btc-bin::,conf::,height::,match-type::,type::,target:,verbose,cookie::,host::,port::,user::" -o "hb::c::g::m::p::t:vC::H::P::U::" -a -- "$@")

eval set -- "$options"

while true
do
	case "$1" in
		-h|--help)
			usage ;;
		-b|--btc-bin)
			shift ; export btcbin="$1" ;;
		-c|--conf)
			shift ; export btcconf="$1" ;;
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
		-C|--cookie)
			shift ; export rpccookie="$1"
			checkUserAndCookie
			;;
		-H|--host)
			shift ; export rpchost="$1" ;;
		-P|--port)
			shift ; export rpcport="$1" ;;
		-U|--user)
			shift ; export rpcuser="$1"
			checkUserAndCookie
			;;
		--)
			shift ; break ;;
	esac
	shift
done

if [ -z "$target" ]; then
	echo "Error: -t|--target option is mandatory." >&2
	exit 1
fi

if [ -n "$btcconf" ]; then
	export btcopts=" -conf=$btcconf"
fi

if [ -n "$rpchost" ]; then
	export btcopts="$btcopts -rpcconnect=$rpchost"
fi

if [ -n "$rpcport" ]; then
	export btcopts="$btcopts -rpcport=$rpcport"
fi

if [ -n "$rpcuser" ]; then
	export btcopts="$btcopts -rpcuser=$rpcuser"
	passwordPrompt
fi

if [ -n "$rpcpass" ]; then
	export btcopts="$btcopts -rpcpassword=$rpcpass"
fi

export btccmd="$btcbin $btcopts"

if [ -z "$height" ]; then
  export height=`$btccmd getblockchaininfo | jq ".blocks"`
fi

for ((i=$height; i>=1; i--)); do
	BLKHSH=`$btccmd getblockhash $i`

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
		TXIDS=`$btccmd getblock $BLKHSH | jq -r ".tx[]"`

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
		TXIDS=`$btccmd getblock $BLKHSH | jq -r ".tx[]"`

		for TXID in $TXIDS; do
			logger "-- Checking txid $TXID at height $i"
			ADDYS=`$btccmd getrawtransaction $TXID true $BLKHSH | jq -r ".vout | map({scriptPubKey})[].scriptPubKey.address | select( . != null )"`

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
