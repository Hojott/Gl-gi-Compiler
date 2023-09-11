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
    # Note the compiler uses only associative arrays (declare -A),
    # and they must be inputed in ${(kv)array} format
    flag="$1" && shift
    local IFS=":"
    [[ "$flag" == "-c" ]] && echo "$*" && return

    echo "$*" | read -r -A array
    declare -A output
    for i in "${array[@]}" ; do
	[[ -z "$previous" ]] && previous=$i && continue
	output["$previous"]=$i && previous=""
    done
    
    echo $output
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

# Create required boilerplate
try -q "Creating global _start" $(echo "\tglobal _start\n\n\t_start:\n" >> $text)

# Helpful variables
log -q "Setting variables"
declare -A variables
variables=(
    # var_name (type var_type size var_size value var_value)
)

# Start compiling code - where the magic happens
log -q "Starting while loop"
line_num=0
while [[ -n "$(cat $tmpsrc)" ]] ; do
    ((line_num++))
    
    line="$(head -n 1 $tmpsrc)"
    cmd="$(split $line -f1)"

    log -q "$src:$line_num Compiling $cmd: $line"

    # Builtin commands
    case "$cmd" in
    "dec")
	# Declare variables
	# Types include int and str
	# String must have their max length appended e.g. str.12
	# Integers must have their byte size e.g. int.32
	# dec int.16 num 17
	# Note while it is possible to redefine variables, it is
	# better practice to revalue them with rev

	# Needed info for variable creation
	var_type_expanded="$(split $line -f2)"
	var_type="$(split $var_type_expanded -d. -f1)"
	var_size="$(split $var_type_expanded -d. -f2)"
	var_name="$(split $line -f3)"
	var_value="$(split $line -f4)"

	case $var_type in
	int)
	    # Variable declaration in Assembly
	    if [[ " $var_name " != *" ${(k)variables} "* ]] ; then
		log -q "New variable $var_name"
	    	echo "\t$var_name resb $((var_size/8))" >> $bss
	    fi

	    # Set variable value in Assembly
	    if [[ -n "$var_value" ]] ; then
	        echo "\t\t; $line" >> $text
	        echo "\t\tmov word [$var_name], $var_value" >> $text
	    fi

	    # Set variable in compiler
	    declare -A $var_info
	    var_info=( "type" "$var_type" "size" "$var_size" "value" "$var_value" )
	    variables["$var_name"]=$(pack -c $var_info)
	;;
	str)
	    :
	;;
	*)
	    fail "Type not found: $var_type_extended" 2
	;;
	esac
    ;;
    "rev")
	# Revalue a variable
	# Type is not needed here, only name and value
	# rev num 4
    ;;
    "yell")
	# Basic print/- command
	# outputs string to stdout
	:
    ;;
    "//*")
	# Comments are marked with //
	# TODO: Move to beginning of while loop / standard library
	:
    ;;
    "*")
	fail "Compilation error: $cmd not found" 2
    ;;
    esac

    sed -i "1d" $tmpsrc
done

# Unite the sections into one file
try -q "Moving bss to dest" $(cat $bss >> $asmfile)
try "" echo "\n" >> $asmfile
try -q "Moving text to dest" $(cat $text >> $asmfile)
try "" echo "\n" >> $asmfile
try -q "Moving data to dest" $(cat "$data" >> $asmfile)

# Compile assembly
try "Compiling nasm..." nasm -f elf $asmfile
try "Compiling ld..." ld -m elf_i386 -s -o $dest $dest.o

