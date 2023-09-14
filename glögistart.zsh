
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

