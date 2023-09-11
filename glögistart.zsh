
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
		# TODO: Integer size validation
	    	echo "\t$var_name resb $((var_size/8))" >> $bss
	    fi

	    # Set variable value in Assembly
	    if [[ -n "$var_value" ]] ; then
	        echo "\t\t; $line" >> $text
		# TODO: Fix to work with others than i16
	        echo "\t\tmov word [$var_name], $var_value" >> $text
		echo "" >> $text
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
	message="$(split $line -f2)"

	echo "\tyell$line_num db \"$message\", 10, 0" >> $data
	echo "\tlen equ \$-yell$line_num" >> $data

	echo "\t\t; $line" >> $text
	echo "\t\tmov eax, 4" >> $text
	echo "\t\tmov ebx, 1" >> $text
	echo "\t\tmov ecx, yell$line_num" >> $text
	echo "\t\tmov edx, len" >> $text
	echo "\t\tint 0x80" >> $text
	echo "" >> $text
	

    ;;
    "exit")
	# Exit program
	# exit 0
	
	exit_code="$(split $line -f2)"
	[[ "$exit_code" == "exit" ]] && exit_code="0"

	echo "\t\t; $line" >> $text
	echo "\t\tmov eax, 1" >> $text
	echo "\t\tmov ebx, $exit_code" >> $text
	echo "\t\tint 0x80" >> $text
	echo "" >> $text
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
try -q "Moving data to dest" $(cat "$data" >> $asmfile)

# Compile assembly
#try "Compiling nasm..." nasm $asmfile
try "Compiling nasm..." nasm -f elf -o $dest.o $asmfile
try "Compiling ld..." ld -m elf_i386 -s -o $dest $dest.o

