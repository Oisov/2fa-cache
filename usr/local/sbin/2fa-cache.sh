#!/bin/bash

# Script: 2fa_cache
# Location: /usr/local/sbin/2fa_cache

# This script provides two-factor authentication (2FA) local cache for user logins. 
# It is designed to be added to the PAM stack where it verifies that a specific token
# exists and has not expired. The script uses tokens stored in files within
# TWO_FACTOR_DIR. Before an user is prompted an 2fa code, we will check the cache
# If we have a file not older than X minutes, we will say the user is validated.
# See help for more information about how to use this script

readonly TWO_FACTOR_DIR="/var/tmp/2fa"
readonly SALT="$HOSTNAME"

hash_string() {
  local string="$1"
  if [ -z "${string}" ]; then
      echo "This function hashes a given string (typically a username) with the system's"
      echo "hostname as a salt."
      echo "Usage: $0 hash <string>"
      exit 1
  fi
  echo -n "${SALT}${string}" | sha256sum | cut -d' ' -f1
}

check_usage() {
    echo "Usage: $0 check <user> <rhost> <minutes>"
    echo ""
    echo "Check for a valid token for the specified user from a particular host"
    echo "within a certain time frame."
    echo ""
    echo "Examples:"
    echo "  $0 check doe 192.168.1.2 60    : Check if doe has a 192.. token from within 60 minutes"
    echo ""
    echo "Arguments:"
    echo "  user     The username to check."
    echo "  rhost    The remote host."
    echo "  minutes  The timeframe in minutes to consider."
    echo ""
    echo "Options:"
    echo -e "  -h, --help\t\tDisplay this help message and exit."
}

check() {
    if [ "$#" -eq 0 ]; then
        check_usage
        exit 0
    fi
    for arg in "$@"; do
        if [[ "$arg" == "-h" ]]; then
            check_usage | head -n1
            exit 0
        elif [[ "$arg" == "--help" ]]; then
            check_usage
            exit 0
        fi
    done
    if [ "$#" -ne 3 ]; then
        check_usage | head -n1
        echo ""
        echo "ERROR: Expected exactly 2 arguments." >&2
        exit 1
    fi
    [[ ! -d "$TWO_FACTOR_DIR" ]] && exit 1

    local username="$1"
    local rhost="$2"
    local minutes="$3"
    local user_path="${TWO_FACTOR_DIR}/$(hash_string "${username}")"
    [[ ! -d "$user_path" ]] && return 1
    local token_path="${user_path}/$(hash_string "${username}${rhost}")"
    [[ ! -f "$token_path" ]] && return 1

    local current_time=$(date +%s)
    local file_time=$(stat --format="%Y" "$token_path")
    local minutes_old=$(( (current_time - file_time) / 60 ))

    if [[ "$minutes_old" -gt "$minutes" ]]; then
        # File is older than minutes; remove the file and exit with status 1
        rm -f "$token_path"
        exit 1
    fi
}

add_usage() {
    echo "Usage: $0 add [-h/--help] <user> <rhost>"
    echo ""
    echo "Add a new token for a specified user and remote host."
    echo ""
    echo "Examples:"
    echo "  $0 add doe 192.168.1.2    : Adds a token for doe corresponding to this rhost (IP)"
    echo ""
    echo "Arguments:"
    echo "  user   The username to add."
    echo "  rhost  The remote host."
    echo ""
    echo "Options:"
    echo -e "  -h, --help\t\tDisplay this help message and exit."
}

add() {
    if [ "$#" -eq 0 ]; then
        add_usage
        exit 0
    fi
    for arg in "$@"; do
        if [[ "$arg" == "-h" ]]; then
            add_usage | head -n1
            exit 0
        elif [[ "$arg" == "--help" ]]; then
            add_usage
            exit 0
        fi
    done
    if [ "$#" -ne 2 ]; then
        add_usage | head -n1
        echo ""
        echo "ERROR: Expected exactly 2 arguments." >&2
        exit 1
    fi
    local username="$1"
    local rhost="$2"
    local user_path="${TWO_FACTOR_DIR}/$(hash_string "${username}")"
    mkdir --parents "$user_path"
    local token_path="${user_path}/$(hash_string "${username}${rhost}")"
    [[ ! -e "$token_path" ]] && touch "$token_path"
}

remove_usage() {
    echo "Usage: $0 remove [--force/-f, --help/-h] [pam_user] [rhost]"
    echo ""
    echo "Examples:"
    echo "  $0 remove --force            : Removes all tokens for all users."
    echo "  $0 remove doe --force        : Removes all tokens for doe"
    echo "  $0 remove doe                : Try to remove all user tokens, error if tokens exceeds 1"
    echo "  $0 remove doe 192.168.1.2    : Remove the token corresponding to user and rhost"
    echo ""
    echo "Arguments:"
    echo "  pam_user   The username to remove."
    echo "  rhost      The remote host to remove"
    echo ""
    echo "Options:"
    echo -e "  -f, --force   Required when removing more than 1 token."
    echo -e "  -h, --help\t\tDisplay this help message and exit."
}

remove() {
    if [ "$#" -eq 0 ]; then
        remove_usage
        exit 0
    fi
    for arg in "$@"; do
        if [[ "$arg" == "-h" ]]; then
            remove_usage | head -n1
            exit 0
        elif [[ "$arg" == "--help" ]]; then
            remove_usage
            exit 0
        fi
    done

    local force_flag=0
    local username=""
    local rhost=""

    if [[ "$1" == "--force" || "$1" == "-f" ]]; then
        force_flag=1
        shift
    fi

    [[ ! -z "$1" ]] && username="$1"
    [[ ! -z "$2" ]] && rhost="$2"

    local dirs_to_remove=()
    local files_to_remove=()

    if [[ -z "${username}" ]]; then
        dirs_to_remove=("${TWO_FACTOR_DIR}"/*/)
    else
        local user_path="${TWO_FACTOR_DIR}/$(hash_string "${username}")"
        if [[ -z "${rhost}" ]]; then
            dirs_to_remove=("${user_path}")
        else
            local token_path="${user_path}/$(hash_string "${username}${rhost}")"
            files_to_remove=("${token_path}")
        fi
    fi

    for dir in "${dirs_to_remove[@]}"; do
        [[ -d "${dir}" ]] && files_to_remove+=("${dir}"/*)
    done

    if ([[ "${#dirs_to_remove[@]}" -gt 1 ]] || [[ "${#files_to_remove[@]}" -gt 1 ]]) && [[ "${force_flag}" -eq 0 ]]; then
        echo "Multiple files or directories to remove. Use '--force' to proceed."
        return 1
    fi

    for file in "${files_to_remove[@]}"; do
        rm "${file}"
    done
    for dir in "${dirs_to_remove[@]}"; do
        rmdir "${dir}" 2>/dev/null
    done
}

# Utility function for displaying usage information
usage() {
    echo "Usage: $0 {-h/--help] <check|add|remove>"
    echo ""
    echo "Commands:"
    echo -e "  check <user> <rhost> <minutes>        Check if a valid token exists within the specified minutes."
    echo -e "  add <user> <rhost>                    Add a new token for a given user and rhost."
    echo -e "  remove [-f/--force] [user] [rhost]    Remove a token for a given user and rhost."
    echo -e "                                        -f/--force is required when multiple tokens is to be removed"
    echo "Options:"
    echo -e "  -h, --help\t\tDisplay this help message and exit."
}


# Assume the first argument is the subcommand if -h or --help is not present
SUBCOMMAND="$1"

# Check if -h or --help is present in the arguments
if [ "$#" -eq 0 ] || [[ "$SUBCOMMAND" == "--help" ]]; then
    usage
    exit 0
fi
if [[ "$SUBCOMMAND" == "-h" ]] ; then
    usage | head -n1 
    exit 0
fi

shift

MINUTES="$1"

# Parse the rest of the arguments based on the SUBCOMMAND
case "$SUBCOMMAND" in
    check)
        check "$PAM_USER" "$PAM_RHOST" "$MINUTES"
        ;;
    add)
        add "$PAM_USER" "$PAM_RHOST"
        ;;
    remove)
        remove "$PAM_USER" "$PAM_RHOST"
        ;;
    *)
        echo "subcommand: \"$SUBCOMMAND\" not in list (check|add|remove)" >&2
        usage
        exit 1
        ;;
esac
