#!/bin/sh
. ar.functions.sh

############################# Constants ################################
motor_serial_path="/dev/ttyO0"


####################### Motor control functions ########################

motor1=0
motor2=0
motor3=0
motor4=0

# motor_open   && [if_ok] || [if_error]
motor_open(){
	serial_open Motor "$motor_serial_path" 115200
	return $?
}

# motor_error_get && [if_error] || [if_ok]
motor_error_get(){
	gpio_input 176 && {
		log "[INFO] Motor cut-off detected!"
		return 0
	}
	return 1
}

# motor_error_reset && [if_ok] || [if_error]
motor_error_reset(){
	gpio_output 175 0
	usleep 1000
	gpio_output 175 1
	gpio_input 176 && {
		log "[WARN] Failed to reset motor error flag!"
		return 1
	}
	return 0
}


################## Motor speed functions #################

# motor_speed <N> <0-511>
motor_speed(){
	local N=$1 value-$2

	eval "motor$N=$value"
	debug "Set motor $N to $value"
}

# motor_send <motor1> <motor2> <motor3> <motor4>
motor_speed_send(){
	local a=$1 b=$2 c=$3 d=$4

	o00=0
	o01=$(( 4 | ( ($a >> 7) & 3) ))
	o02=$(( ($a >> 4) & 7 ))
	o10=$(( ($a >> 2) & 3 ))
	o11=$(( ( ($a & 3) << 1 ) | ( ($b >> 8) & 1) ))
	o12=$(( ($b >> 5) & 7 ))
	o20=$(( ($b >> 3) & 3 ))
	o21=$(( $b & 7 ))
	o22=$(( ($c >> 6) & 7 ))
	o30=$(( ($c >> 4) & 3 ))
	o31=$(( ($c >> 1) & 7 ))
	o32=$(( ( ($c & 1) << 2 ) | ( ($d >> 7) & 3 ) ))
	o40=$(( ($d >> 5) & 3 ))
	o41=$(( ($d >> 2) & 7 ))
	o42=$(( ($d & 3) << 1 ))

	eval "echo -ne \"\\0$o00$o01$o02\\0$o10$o11$o12\\0$o20$o21$o22\\0$o30$o31$o32\\0$o40$o41$o42\"" | \
		echo "$(serial_send Motor 0 $(bytes2hex))"

	[ $? -ne 0 ] && {
		motor_error_get && return 1
	}
	return 0
}
