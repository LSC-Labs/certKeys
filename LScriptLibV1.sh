# LSC scripting library
#
# (c) 1990-2024 LSC P.Liebl
#

# Read a single key from stdin (console)
# First paramter is the message to be displayed like "OK ? [Y/n]"
# Second parameter is the default key - if enter is pressed. In this sample "Y"
# Third parameter is a regular expression with the keys allowed to be pressed.
# - in the sample above "[YNyn]" would allow upper and lower case of the key Y and N
# Default - every key is allowed, Default answer would be ""
readKey() {
    local strMessage=${1:-""}
    local strDefaultAnswerKey=${2:-""}
    local strRegExMatch=${3:-"."}
    local strAnswerKey="${strDefaultAnswerKey:0:1}"
    local bIsMatch=0
    while [ "${bIsMatch}" == "0" ]; 
    do
        read -n 1 -s -p "$strMessage" strAnswerKey
        if [ "$strAnswerKey" == "" ]; then strAnswerKey=${strDefaultAnswerKey:0:1}; fi
        [[ $strAnswerKey =~ $strRegExMatch ]] && bIsMatch=1;
        strMessage=""
    done
    echo $strAnswerKey
}


# Trace command, writes to the stderr channel.
# if the switch -trace is set, a trace entry will be written to stdout:
trace() {
    local TraceFlag=$(getArgumentSwitchValue 'trace')
    if $( isTrueString "${TraceFlag}" ); 
    then 
        printf "[T]" >&2 ;
        while [ "${1}" != "" ];
        do
            printf " %s" "$1" >&2 ;
            shift
        done
        printf "\n" >&2 ;
    fi
}

# checks if the value represents a true state
# +, 1, true, y are resulting in true
# -, 0, false and the rest are resulting in false
isTrueString() {
    if [ "$1" != "" ]; then
        # define only explicit the false values !!!
        # true values can be inside (for documentation)
        case "${1:L}" in
            "true")  
                true
                ;;
            "false") 
                false
                ;;
            "no")
                false
                ;;
            "n")
                false
                ;;
            "0")     
                false
                ;;
            "1")
                true
                ;;
            "-")     
                false
                ;;
            "+")     
                true
                ;;
            *) 
                true
                ;;
        esac
    else
        ## Nothing received - this is false !
        false
    fi
}

# Get the string before the token.
# If token is not in place, the default will be returned (the text)
# $1 = string to be checked
# $2 = token to be used (default = " ")
# $3 = Default if token is not in place ($1)
stringBefore() {
    local strText=$1
    local strToken=${2:-" "}
    local strDefault=${3:-$1}
    local strResult="${strText%$strToken*}"
    if [ "$strText" == "$strResult" ]; then strResult=$strDefault; fi
    echo $strResult
}

# Get the string after the token.
# If token is not in place, the default will be returned ("")
# $1 = string to be checked
# $2 = token to be used (default = " ")
# $3 = Default if token is not in place ("")
stringAfter() {
    local strText=$1
    local strToken=${2:-" "}
    local strDefault=${3:-""}
    local strResult="${strText#*$strToken}"
    if [ "$strText" == "$strResult" ]; then strResult=$strDefault; fi
    echo $strResult

}

getArgumentSwitchValue() {
    local strSwitch="${1@L}"
    local strDefault=${2:-""}
    local strValue="${tArgSwitches[$strSwitch]}"
    echo "${strValue:-$strDefault}"
}

setArgumentSwitchValue() {
    local strSwitchName=${1@L}
    local strSwitchValue=$2
    tArgSwitches[${strSwitchName}]=$strSwitchValue
    trace "Setting switch $strSwitchName to $strSwitchValue"
}

# Set a commandline switch (to a default)
# so call before
setArgumentSwitchIfNotSet() {
    local strSwitchName=$1
    local strSwitchValue=$2
    local strValue=$(getArgumentSwitchValue "$strSwitchName")
    if [ -v $strValue ];
    then
        setArgumentSwitchValue "$strSwitchName" "$strSwitchValue"
    fi
}

dumpKnownArgumentSwitches() {
    echo "Known argument switches are set to:"
    echo "-----------------------------------"
    for strKey in "${!tArgSwitches[@]}"
    do
        printf " - %-15s: %s\n" "$strKey" "${tArgSwitches[$strKey]}"
    done
}

dumpKnownUnnamedArguments() {
    echo "Known unnamed arguments are set to:"
    echo "-----------------------------------"
    local nArraylength=${#tUnnamedArguments[@]}
    for (( i=0; i<${nArraylength}; i++ ));
    do
        printf "%2d) %s\n" $i "${tUnnamedArguments[$i]}"
    done
}

# this 2 lines are necessary to process the setArgumentsFromUser correctly
# the tCommandlineArguments as table of the original arguments, as they are
# not correctly handled if you call a function. Then arguments with blanks
# are splitted in more arguments.
# tArgSwitches has to be global and stores all switches "-xxx" from the cmdline
tCommandLineArguments=("$@")
declare -A tArgSwitches

# Set the arguments from commandline
# All arguments, that ar no switeches are stored inside the hashtable tUnnamedArguments.
# If a switch is set alone, it is set to 1 (true)
# otherwise the first param following the switch is set to it's value.
setArgumentsFromCommandLine() {
    local nElements=${#tCommandLineArguments[@]}
    local nCurElement=0
    while [ "$nCurElement" -lt "$nElements" ];
    do
        local strArg="${tCommandLineArguments[$nCurElement]}"
        if [ "${strArg:0:1}" = "-" ]; 
        then
            local strSwitch="${strArg:1}"
            local strValue="${tCommandLineArguments[$nCurElement + 1]}"
            if [ "${strValue}" == "" ] || [ "${strValue:0:1}" = "-" ]; 
                then strValue="1"; 
                else (( nCurElement++ ))
            fi
            setArgumentSwitchValue "$strSwitch" "$strValue"
        else 
            tUnnamedArguments+=("${strArg}")
        fi
        (( nCurElement++))
    done
}

# Default operation - parse the arguments from user
setArgumentsFromCommandLine

## Set the remaining unnamed arguments so they can be processed by the program
## To avoid this, set LS_KEEP_ARGUMENTS="true"
if  $(! isTrueString "$LS_KEEP_ARGUMENTS" );
then 
    set -- "${tUnnamedArguments[@]}"
fi 

