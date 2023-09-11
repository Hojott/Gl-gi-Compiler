#!/bin/zsh
##
## The glögi compiler, written in zsh.
##
echo "Initializing compiler..."

# Load zsh modules
#autoload ...

# Create utility functions
log() {
    # $1: command flag (-q to silence, -qq to supersilence)
    # $2: loggable message
    [[ -n "$2" ]] && message="$2" || message="$1"
    [[ -n "$logfile" ]] && echo "$message" >> "$logfile" || echo "$message" >> glögilogs
    if [[ "$1" == "-qq" ]] ; then
	:
    elif [[ "$1" == -q ]] && [[ -z "$verbose" ]] ; then
	:
    else
    	echo "$message"
    fi
}

fail() {
    # $1: error message
    # $2: error code (default 1)
    message="FAILED: $1"
    log -qq "$message"
    echo "$message" 1>&2
    [[ -n $2 ]] && exit $2 || exit 1
}

try() {
    # $1: command flags (-q to silence, -e to add error message)
    # $2: message, like what the command is doing. Leaving empty will not print anything
    # $3: if -e passed, it is space for error message
    # $@: Command to execute
    # Note conditions must be passed with test and declaring variables must be done globally
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
}

# Reset logs
echo "Initializing compiler" > glögilogs

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
	cat glögilogs | tail --lines=+2
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
	for f in $(echo "$1" | sed -e 's/\(.\)/\1\n/g') ; do
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
		cat glögilogs
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
[[ -z "$dest" ]] && dest="$(echo $src | cut -d. -f1)" # src cut at first dot
[[ -f "$dest" ]] && [[ ! $force ]] && fail "Destination with same name found. Use --force to override"

# Move logfile
[[ -n "$logfiletmp" ]] && logfile=$logfiletmp || logfile="$dest.log" ; mv glögilogs $logfile

# Start compilation
try - "Creating destination..." touch $dest

