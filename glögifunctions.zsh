
### Builtin functions ###
log -q "Creating builtin functions..."

# Create constants
declare -a int_sizes
int_sizes=( 16 32 64 )

# Create compiling functions
validate_value() {
    # validate_value "var/value"
    # $1: variable/value
    # Returns variable value if input is a glögi variable,
    # or returns back the value in assembly-format
    # e.g validate_value "hello" -> hello
    #     validate_value variable -> 5
    input=$1
    case $input in
    \'*\'|\"*\")
	# case string, remove quotes
	value=$(split $input -d"'" -f2)
    ;;
    +([[:digit:]]))
	# case integer, remove +
	value=$(split $input -d"+" -f2)
    ;;
    *)
	# case variable
	if [[ " $input " == *" ${(k)variables} "* ]] ; then
	    var_info=$(pack -x ${variables[$input]})
	    [[ "${var_info[var_type]}" == "int" ]] && value="[$input]"
	    [[ "${var_info[var_type]}" == "str" ]] && value=$input
	else
	    fail "$input not defined!" 2
	fi
    ;;
    esac
    
    echo $value
}

# Create usable builtin functions for the language
builtin_exit() {
    # Exit program
    # exit 0
	
    exit_code="$1"
    [[ -z "$exit_code" ]] && exit_code="0"

    echo "\t\t; $line" >> $text
    echo "\t\tmov eax, 1" >> $text
    echo "\t\tmov ebx, $exit_code" >> $text
    echo "\t\tint 0x80" >> $text
    echo "" >> $text
}

builtin_create() {
    # Create a new variable
    # create int.16 car_id
    # Integers must have their bit-size appended to type
    # String must have their max length appended

    # Get parameters
    var_type_expanded="$1"
    var_type="$(split $var_type_expanded -d. -f1)"
    var_size="$(split $var_type_expanded -d. -f2)"
    var_name="$2"

    [[ " $var_name " == *" ${(k)variables} "* ]] && fail "Variable already created!" 2

    case $var_type in
    int)
	# Variable declaration in .bss
	if (( $int_sizes[(Ie)$var_size] )) ; then
	    echo "\t$var_name resb $((var_size/8))" >> $bss
	else
	    fail "Int cannot be $var_size-bit!" 2
        fi
	
    ;;
    str)
	# Variable declaration in .bss
	#echo "\t$var_name resb $((var_size*2))" >> $bss

	# Variable declaration in .data
	#echo "\t$var_name db \"$var_value\", 0" >> $data

    ;;
    *)
	fail "Type not found: $var_type_extended" 2
    ;;
    esac

    # Set variable in compiler
    variables["$var_name"]="$var_type:$var_size:"

}

builtin_rev() {
    # Revalue a variable
    # rev car_id 17
    # Variables must be created first

    # Get parameters
    var_name="$1"
    var_value="$2"

    # Get existing variable info
    [[ " \"$var_name\" " == *" ${(k)variables} "* ]] || fail "Variable hasn't been created!" 2
    
    # Unpack variable info
    var_info=${variables["$var_name"]}

    var_type="$(split $var_info -d":" -f1)"
    var_size="$(split $var_info -d":" -f2)"
    var_info=""

    case $var_type in
    int)
	# Set variable value in .text
        (( $int_sizes[(Ie)$var_size] )) || fail "Invalid variable size set!" 2
	echo "\t\t; $line" >> $text

	# Set correct word size
	case "$var_size" in
	16)
	    echo "\t\tmov word [$var_name], $var_value" >> $text
	;;
	32)
	    echo "\t\tmov dword [$var_name], $var_value" >> $text
	;;	
	64)
	    echo "\t\tmov qword [$var_name], $var_value" >> $text
	;;	
        esac

	echo "" >> $text
    ;;
    str)
	# Variable declaration in .bss
	#if [[ " $var_name " != *" ${(k)variables} "* ]] ; then
	#	echo "\t$var_name resb $((var_size*2))" >> $bss
	#fi

	# Variable declaration in .data
	#echo "\t$var_name db \"$var_value\", 0" >> $data

    ;;
    *)
	fail "Type not found: $var_type.$var_size" 2
    ;;
    esac

    # Set variable in compiler
    variables["$var_name"]="$var_type:$var_size:$var_value"
}

builtin_yell() {
    # Basic print/- command
    # outputs string to stdout
    message="$1"

    # Changes to .data
    echo "\t__yell$line_num db \"$message\", 10, 0" >> $data
    echo "\t__len$line_num equ \$-__yell$line_num" >> $data

    # Changes to .text
    echo "\t\t; $line" >> $text
    echo "\t\tmov eax, 4" >> $text
    echo "\t\tmov ebx, 1" >> $text
    echo "\t\tmov ecx, __yell$line_num" >> $text
    echo "\t\tmov edx, __len$line_num" >> $text
    echo "\t\tint 0x80" >> $text
    echo "" >> $text
}
