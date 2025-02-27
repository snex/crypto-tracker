#!/bin/bash

usage() {
	cat << EOF
Usage: $0 -t <target> [-hbcgmpvCHPU]
Hunt for a Bitcoin Cash block hash / transaction / address based on a partial match

-h, -help,		--help		Display help

-b, -bch-bin,		--bch-bin	Path to bitcoin-cli
					Default will look in PATH

-c, -conf,		--conf		Path to bitcoin.conf, if necessary
					Default is blank

-g, -height,		--height	Height to start searching from
					Searches go from <height> down to 1
					Defaults to the current height

-m, -match-type,	--match-type	Type of match to look for
					Possible values are "any", "start", "end"
					This flag is ignored if target type is "amount"
					Default is "any"

-p, -type,		--type		The type of target to hunt for
					Possible values are "hash", "txid", "address", "amount"
					Default is "hash"

-t, -target,		--target	The target string to hunt for, required

-v, -verbose,		--verbose	Enable verbose mode

-C, -cookie,		--cookie	RPC auth cookie
					Do not use combined with --user

-H, -host,		--host		Host for Bitcoin Cash RPC daemon
					Default is 127.0.0.1

-P, -port,		--port		Port for Bitcoin Cash RPC daemon
					Default is 8332

-U, -user,		--user		RPC username
					If present, password will be prompted for
					Do not use combined with --cookie
EOF
exit 0
}

checkType() {
	if [[ "$targettype" =~ ^(hash|txid|address|amount)$ ]]; then
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

export bchbin=`which bitcoin-cli`
export bchconf=""
export height=""
export matchtype="any"
export targettype="hash"
export verbose=0
export rpccookie=""
export rpchost="127.0.0.1"
export rpcport="8332"
export rpcuser=""
export rpcpass=""
export bchopts=""


[ $# -eq 0 ] && usage
options=$(getopt -l "help,bch-bin::,conf::,height::,match-type::,type::,target:,verbose,cookie::,host::,port::,user::" -o "hb::c::g::m::p::t:vC::H::P::U::" -a -- "$@")

eval set -- "$options"

while true
do
	case "$1" in
		-h|--help)
			usage ;;
		-b|--bch-bin)
			shift ; export bchbin="$1" ;;
		-c|--conf)
			shift ; export bchconf="$1" ;;
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

if [ -n "$bchconf" ]; then
	export bchopts=" -conf=$bchconf"
fi

if [ -n "$rpchost" ]; then
	export bchopts="$bchopts -rpcconnect=$rpchost"
fi

if [ -n "$rpcport" ]; then
	export bchopts="$bchopts -rpcport=$rpcport"
fi

if [ -n "$rpcuser" ]; then
	export bchopts="$bchopts -rpcuser=$rpcuser"
	passwordPrompt
fi

if [ -n "$rpcpass" ]; then
	export bchopts="$bchopts -rpcpassword=$rpcpass"
fi

if [ -n "$rpccookie" ]; then
	export bchopts="$bchopts -rpccookiefile=$rpccookie"
fi

export bchcmd="$bchbin $bchopts"

if [ -z "$height" ]; then
	export height=`$bchcmd getblockchaininfo | jq ".blocks"`
fi

for ((i=$height; i>=1; i--)); do
	BLKHSH=`$bchcmd getblockhash $i`

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
		TXIDS=`$bchcmd getblock $BLKHSH | jq -r ".tx[]"`

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
		TXIDS=`$bchcmd getblock $BLKHSH | jq -r ".tx[]"`

		for TXID in $TXIDS; do
			logger "-- Checking txid $TXID at height $i"
			ADDYS=`$bchcmd getrawtransaction $TXID true $BLKHSH | jq -r ".vout | map({scriptPubKey})[].scriptPubKey.addresses | select( . != null )"`

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
	elif [[ $targettype == "amount" ]]; then
		TXIDS=`$bchcmd getblock $BLKHSH | jq -r ".tx[]"`

		for TXID in $TXIDS; do
			logger "-- Checking txid $TXID at height $i"
			AMOUNTS=`$bchcmd getrawtransaction $TXID true $BLKHSH | jq -r ".vout | map({value})[].value"`

			for AMOUNT in $AMOUNTS; do
				logger "---- Checking amount $AMOUNT"

				AMOUNT=`sed -E 's/([+-]?[0-9.]+)[eE]\+?(-?)([0-9]+)/(\1*10^\2\3)/g' <<<"$AMOUNT" | bc -l`

				if [[ "`echo "$AMOUNT==$target" | bc -l`" -eq 1 ]]; then
					echo "Found amount matching $target at height $i in transaction ID $TXID!"
					exit 0
				fi
			done
		done
	fi
done
