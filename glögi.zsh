#!/bin/zsh
##
## The glögi compiler, written in zsh.
##

### Start initialization ###
echo "Initializing compiler..."

# Load zsh modules
#autoload ...

# Create utility functions
# TODO: better names for tmp_log and logfiletmp
tmp_log="glögi.log"
log() {
    # log [-qq] "log"
    # $1: command flag (-q to silence, -qq to supersilence)
    # $2: loggable message
    [[ -n "$2" ]] && message="$2" || message="$1"
    [[ -n "$logfile" ]] && echo "$message" >> "$logfile" || echo "$message" >> "$tmp_log"
    if [[ "$1" == "-qq" ]] ; then
	:
    elif [[ "$1" == -q ]] && [[ -z "$verbose" ]] ; then
	:
    else
    	echo "$message"
    fi
}

fail() {
    # fail "error" ["code"]
    # $1: error message
    # $2: error code (default 1)
    # On error codes, 
    message="FAILED: $1"
    log -qq "$message"
    echo "$message" 1>&2
    [[ -n $2 ]] && exit $2 || exit 1
}

try() {
    # try [-qe] "message" ["error"] command
    # $1: command flags (-q to silence, -e to add error message)
    # $2: message, like what the command is doing. Leaving empty will not print anything
    # $3: if -e passed, it is space for error message
    # $@: Command to execute
    #
    # Note command are run in function, so e.g conditions must be passed with test, 
    # declaring variables must be done globally, shift doesn't work and
    # outputing to file must be done with $()
    if [[ ${1::1} == "-" ]] ; then
        for f in $(echo "$1" | sed -e 's/\(.\)/\1\n/g') ; do
	    case "$f" in
	    -)
	    	continue
	    ;;
	    e)
	    	include_error="yes"
	    ;;
	    q)
	    	quiet="yes"
	    ;;
	    c)
		# TODO: implement errorcodes
		error_code="yes"
	    ;;
	    esac
    	done
	shift
    fi
    message="$1"
    shift
    [[ -n "$include_error" ]] && { error="$1" ; shift }
    if [[ -n "$quiet" ]] ; then
	[[ -n "$message" ]] && log -q "$message"
    else
	[[ -n "$message" ]] && log "$message"
    fi
    if "$@" ; then
	:
    else
	[[ -n "$quiet" ]] && echo $message
	[[ -n "$error" ]] && fail "$error" || fail "$*"
    fi
    # Reset
    include_error=""
    quiet=""
    error_code=""
}

split() {
    # split "command" [-cutflags]
    # $1: Command/string to cut
    # $@: Flags passed to cut
    # Most basic flag is -f1, which returns the first word
    full_str="$1" && shift
    str="$(echo "$full_str" | cut - -d" " $*)"
    echo "$str"
}

pack() {
    # pack [-cx] "string/array"
    # $1: Flag (-c create/pack, -x export/unpack)
    # $2: Packed string or packable array
    # In SH it is quite hard to place arrays inside arrays,
    # so they are packed into strings that can be unpacked
    # Note pack() uses only associative arrays (declare -A),
    # and they must be inputed in ${(kv)array} format
    flag="$1" && shift
    local IFS=":"
    [[ "$flag" == "-c" ]] && output="$*"
    
    if [[ "$flag" == "-x" ]] ; then
    	echo "$*" | read -r -A array
    	declare -A output
	for i in "${array[@]}" ; do
	    [[ -z "$previous" ]] && previous=$i && continue
	    output[$previous]="$i" && previous=""
    	done
    fi
    
    echo ${output[@]}
}

# Reset logs
echo "Initializing compiler" > "$tmp_log"

# Check command flags
log -q "Checking args"

while [[ -n $1 ]] ; do
    case "$1" in
    --dest|-d)
	try -qe "Found dest-flag: $2" "Missing parameter for $1" test -z "$2" && declare -g dest="$2"
	shift
    ;;
    --force|-f)
	log -q "Found force-flag"
	force="yes"
    ;;
    --verbose|-v)
	cat "$tmp_log" | tail -n +2
	log "Found verbose-flag: starting verbose-mode"
	verbose="yes"
    ;;
    --logfile|-l)
	try -qe "Found log-flag: $2" "Missing parameter for $1" test -n "$2" && declare -g logfiletmp="$2"
	shift
    ;;
    --*)
	fail "$1: no flag with that name"
    ;;
    -*)
	for f in $(echo "$1" | sed -e 's/\(.\)/\1\n/g') ; do # TODO: find out how this works
	    case "$f" in 
	    -)
	    	continue
	    ;;
	    d)
		try -qe "Found dest-flag: $2" "Missing parameter for -$f" test -n "$2" && declare -g dest="$2"
	    	shift
	    ;;
	    f)
		log -q "Found force-flag"
	    	force="yes"
	    ;;
	    v)
		cat "$tmp_log" | tail -n +2
		log "Found verbose-flag: starting verbose-mode"
	    	verbose="yes"
	    ;;
    	    l)
		try -qe "Found log-flag: $2" "Missing parameter for -$f" test -n "$2" && declare -g logfiletmp="$2"
		shift
	    ;;
	    *)
	    	fail "-$f: no flag with that name"
	    ;;
    	    esac
	done
    ;;
    *)
	try -qe "Trying source: $1" "Too many parameters!" test -z "$src" && declare -g src="$1"
	log -q "Source selected: $src"
    ;;
    esac
    shift
done

# Validate sourcefile
log -q "Validating sourcefiles"
[[ -z "$src" ]] && fail "No source defined"
[[ ! -f "$src" ]] && fail "No source file found: $src"

# Set default dest
[[ -z "$dest" ]] && dest="$(split $src -d. -f1)" # src cut at first dot
[[ -f "$dest" ]] && [[ ! $force ]] && fail "Destination with same name found. Use --force to override"

# Move logfile
[[ -n "$logfiletmp" ]] && logfile=$logfiletmp || logfile="$dest.log" ; mv "$tmp_log" $logfile


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

    echo $var_info
    var_type="$(split $var_info -d":" -f1)"
    var_size="$(split $var_info -d":" -f2)"
    var_info=""
    echo "$var_type $var_size"

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
    var_info=( "var_type" "$var_type" "var_size" "$var_size" "var_value" "$var_value" )
    variables["$var_name"]=$(pack -c ${(kv)var_info})
    var_info=()
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

### Start compilation ###
log "Starting compilation..."

# Copy src to a tmpfile, so it won't be damaged
tmpsrc=".$src.tmp"
try -q "Creating tmp sourcefile" cp $src $tmpsrc

# Create temporate destfiles for different Assembly sections
# and the final destination file
bss=".$dest.bss.tmp"
try -q "Creating bss-dest" $(echo "section .bss" > $bss)
text=".$dest.text.tmp"
try -q "Creating text-dest" $(echo "section .text" > $text)
data=".$dest.data.tmp"
try -q "Creating data-dest" $(echo "section .data" > $data)

asmfile="$dest.asm"
try -q "Creating assembly file" $(echo "; $dest" > $asmfile)

# Create required boilerplate (1/2)
try -q "Creating global _start" $(echo "\tglobal _start\n\n\t_start:\n" >> $text)

# Helpful variables
log -q "Setting variables"

# Create list of defined variables for compiler
declare -A variables
variables=(
    # (associative) arrays are shit
    # "var_name" "var_type:var_size:var_value"
)

# Mark line nmber
line_num=0

# Start compiling code - where the magic happens
log -q "Starting while loop"
while [[ -n "$(cat $tmpsrc)" ]] ; do
    ((line_num++))
    
    line="$(head -n 1 $tmpsrc)"
    cmd="$(split $line -f1)"

    log -q "$src:$line_num Compiling $cmd: $line"

    # Check command for builtins
    case "$cmd" in
    "create")
	# Create a new variable
	
	# Get parameters
	var_type_expanded="$(split $line -f2)"
	var_name="$(split $line -f3)"
	
	# Check if all parameters are set
	[[ "$var_type_extended" == "$var_name" ]] && fail "Not enough parameters" 2

    	builtin_create $var_type_expanded $var_name

    ;;
    "rev")
	# Revalue a variable
    	
	# Get parameters
	var_name="$(split $line -f2)"
	var_value="$(split $line -f3)"

	builtin_rev $var_name $var_value

    ;;
    "yell")
	# Basic print/- command
	# outputs string to stdout
	message="$(split $line -f2)"

	builtin_yell $message

    ;;
    "exit")
	# Exit program

	# Get parameters
	exit_code="$(split $line -f2)"
	[[ "$exit_code" == "exit" ]] && exit_code="0"
	
	builtin_exit $exit_code
    
    ;;
    "//*"|"")
	# Comments are marked with //
	# TODO: Move to beginning of while loop
	:
    ;;
    "*")
	fail "Compilation error: $cmd not found" 2
    ;;
    esac

    sed -i "1d" $tmpsrc
done

# Create required boilerplate (2/2)
#try -q "Creating end" $(echo "\tend:\n\t\tmov eax, 1\n\t\tmov ebx, 0\n\t\tint 0x80\n" >> $text)

# Unite the sections into one file
try -q "Moving bss to dest" $(cat $bss >> $asmfile)
try "" echo "\n" >> $asmfile
try -q "Moving text to dest" $(cat $text >> $asmfile)
try -q "Moving data to dest" $(cat "$data" >> $asmfile)

# Compile assembly
#try "Compiling nasm..." nasm $asmfile
try "Compiling nasm..." nasm -f elf -o $dest.o $asmfile
try "Compiling ld..." ld -m elf_i386 -s -o $dest $dest.o

