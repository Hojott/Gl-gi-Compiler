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
    --debug|-D)
	log -q "Found debug-flag"
	debug="yes"
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
    	    D)
		log -q "Found debug-flag"
		debug="yes"
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

