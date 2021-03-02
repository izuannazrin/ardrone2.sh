#!/bin/sh

debug(){
	echo "[$0]: $@" >&2
}
log(){
	echo "[$0]: $@" >&2
}


########################### Type conversion functions ##########################

# <bytes[bytes...]> | bytes2hex   | [hex [hex ...]]
bytes2hex(){
	hexdump -ve '1/1 "%02x "'
}

# hex2bytes [hex [hex ...]]   | [bytes[bytes...]]
hex2bytes(){
	for i in $@; do
		echo -ne "\x$i"
	done
}

# <bytes> | bytes2float   | [float [float ...]]
bytes2float(){
	hexdump -ve '1/4 "%e "'
}


########################## GPIO functions ###########################

# gpio_input <gpio>   && [if_high] || [if_low]
gpio_input(){
	local data

	gpio $1 -d i
	data=$(gpio $1 -r | head -n2 | tail -n1 | cut -d':' -f2 | tr -d ' ')
	[ "$data" = "0" ] && return 1 || return 0
}

# gpio_output <gpio> <value>
gpio_output(){
	gpio $1 -d ho $2
}


######################## Motor comm functions #######################

# CS1,CS2,CS3,CS4 -> 171,172,173,174

# CS_set [N [N ...]]
CS_set(){
	for N in $@; do
#		gpio $((170+$N)) -d i
		gpio_input $((170+$N))
		debug "CS$N enabled."
	done
}

# CS_reset [N [N ...]]
CS_reset(){
	for N in $@; do
#		gpio $((170+$N)) -d ho 0
		gpio_output $((170+$N)) 0
		debug "CS$N disabled."
	done
}

# CS <(0|1)> <(0|1)> <(0|1)> <(0|1)>
CS_control(){
	local setting
	for N in 1 2 3 4; do
		eval "setting=\$$N"
		[[ "$setting" = "1" ]] && CS_set $N || CS_reset $N
	done
}


########################## SERIAL I/O ########################

serial_lastfd=3

# serial_open <ref_name> <path> <baudrate>   && [if_ok] || [if_error]
serial_open(){
	local ref_name=$1 path=$2 baudrate=$3
	local fd_in=$serial_lastfd fd_out=$(($serial_lastfd+1))
	serial_lastfd=$(($serial_lastfd+2))

	stty -F "$path" $baudrate min 0 time 5 || {
		log "[WARN] $ref_name: Failed to set serial capability."
		return 1
	}
	exec $fd_in>"$path" $fd_out<"$path" && \
		debug "$ref_name: Serial $path opened on fd $fd_in,$fd_out." || {
		log "[WARN] $ref_name: Failed to open $path."
		return 2
	}

	serial_lastfd=$(($serial_lastfd+2))
	eval "serial_${ref_name}_in=$fd_in"
	eval "serial_${ref_name}_out=$fd_out"
}

# serial_close <ref_name>
serial_close(){
	local ref_name=$1
	local fd_in fd_out

	eval "fd_in=\$serial_${ref_name}_in fd_out=\$serial_${ref_name}_out"
	exec $fd_in>&- $fd_out<&-
	debug "$ref_name: Serial closed."
}

# serial_flush <ref_name>
serial_flush(){
	local ref_name=$1
	local fd_in

	eval "fd_in=\$serial_${ref_name}_in"
	debug "$ref_name: Stray data: $(bytes2hex <&$fd_in)"
	debug "$ref_name: Serial flushed."
}

# serial_send <ref_name> <reply_count> [hex [hex ...]]   | [reply]
# <bytes> | serial_send <ref_name> <reply_count> $(bytes2hex)   | [reply]
serial_send(){
	local ref_name=$1 reply_count=$2
	shift 2
	local cmd="$@ " cmd_count=$#
	local fd_in fd_out
	local reply cmd_echo errno=0

	eval "fd_in=\$serial_${ref_name}_in fd_out=\$serial_${ref_name}_out"

	debug "$ref_name: Sending $cmd_count bytes..."
	debug "$ref_name: cmd=$cmd"
	hex2bytes $cmd >&$fd_in

	[ "$reply_count" = "-1" ] && {
		debug "Ignoring reply! (Use serial_flush after this.)"
		return
	}

	debug "$ref_name: Waiting for reply..."
	reply="$(dd bs=1 count=$(($cmd_count+$reply_count)) 2>/dev/null <&$fd_out | bytes2hex)"
	cmd_echo="${reply:0:$((cmd_count*3))}"
	[ "$cmd_echo" = "$cmd" ] || {
		log "[WARN] $ref_name: cmd echo mismatch!"
		errno=1
	}
	reply="${reply:$((cmd_count*3))}"
	[ $((${#reply} / 3)) -eq $reply_count ] || {
		log "[WARN] Insufficient reply size!"
		errno=2
	}
	debug "$ref_name: cmd=$cmd cmd_echo=$cmd_echo reply=$reply"

	echo -n "$reply"
	return $errno
}
