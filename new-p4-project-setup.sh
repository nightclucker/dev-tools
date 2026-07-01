#!/bin/bash
# This script sets up a new P4 project by creating the necessary directory structure and files.
# Need to run this script with the project name, a valid p4 user name.

# Name of the project
PROJECT_NAME=$1

# Comma delimited list of p4 user names that will be grouped into this project.
# The first user in the list must be the project owner.
PROJECT_USERS=$2
PROJECT_REQUESTER=${PROJECT_USERS%%,*}  # Get the first user from the comma-separated list

# List of streams that need to be created.
MAINLINE_STREAMS="Main ArtSource Tools"
RELEASE_STREAMS="Staging Production Live"

# The depth the depot will be built with.  for example, 2: //Project/1/2
STREAM_DEPTH=2

# Specs for P4 depots.
DEPOT_SPEC="""
Depot: ${PROJECT_NAME}
Owner: ${PROJECT_REQUESTER}
Type: stream
Description: Project depot automatically created on $(date).  Creation requested by ${PROJECT_REQUESTER}.
StreamDepth: ${STREAM_DEPTH}
Map: ${PROJECT_NAME}/...
"""

# Specs for p4 streams.
STREAM_SPEC="""
Stream: //${PROJECT_NAME}/{{{SUB_NAME}}}/{{{STREAM_NAME}}}
Owner: ${PROJECT_REQUESTER}
Name: {{{STREAM_NAME}}}
Type: {{{STREAM_TYPE}}}
Description: Stream depot automatically created on $(date).  Creation requested by ${PROJECT_REQUESTER}.
Parent: {{{STREAM_PARENT}}}
ParentView: {{{PARENT_VIEW}}}
Paths: share ...
"""

# Speces for P4 groups.
P4_GROUP_SPEC="""
Group: ${PROJECT_NAME}
Description: Group automatically created on $(date).  Creation requested by ${PROJECT_REQUESTER}.
MaxResults:	unset
MaxScanRows:	unset
MaxLockTime:	unset
MaxOpenFiles:	unset
MaxMemory:	unset
Timeout:	unset
IdleTimeout:	unset
PasswordTimeout:	unset
Subgroups:
Users:
    $(echo "${PROJECT_USERS}" | sed 's/,/\n    /g')
"""

# Name of the logger found in the system logs.
LOGGER_NAME="p4-project-setup"

# Log Function that takes in two arguments.  The first argument is the log level and the second is the message.
log()
{
    local level="$1"
    shift
    local message="$*"

    echo "[${level}] ${message}"
    logger -t "${LOGGER_NAME}" "[${level}] ${message}"
}

# Checks if the P4 cli tools are installed, otherwise exits.
validate_p4_install()
{
    if [ ! -x "$(which p4)" ]; then
        log "ERROR" "Perforce CLI tools (p4) are not installed or not in the PATH."
        exit 1
    fi
}

# Checks if a p4 user is logged in, otherwise exits.
validate_logged_in_p4_user()
{
    if ! p4 login -s > /dev/null 2>&1; then
        log "ERROR" "p4 user is not logged in."
        exit 1
    fi
}

# Checks if the p4 user is a super user.  Only super users can create depots.  Exit if they are not.
validate_logged_in_p4_users_permissions()
{
    if ! p4 group -o "Super" | grep "$LOGGED_IN_USER" > /dev/null 2>&1; then
        log "ERROR" "Logged in user does not have permission to create depots, streams, or groups!"
        exit 1
    fi
    log "INFO" "Logged in user has permission to create depots, streams, and groups."
}

create_p4_depot()
{
    if ! p4 depots -e "${PROJECT_NAME}" | grep -q "${PROJECT_NAME}" > /dev/null 2>&1; then
        log "INFO" "Depot ${PROJECT_NAME} does not exist. Creating depot..."
        p4 depot -i << EOF
${DEPOT_SPEC}
EOF

        if [ $? -ne 0 ]; then
            log "ERROR" "Failed to create depot ${PROJECT_NAME}."
            exit 1
        fi

        log "INFO" "Depot //${PROJECT_NAME}/... created successfully."
    else
        log "INFO" "Depot //${PROJECT_NAME}/... already exists. Skipping depot creation."
    fi
}

# Creates a stream using a given list of stream names.
# Takes four arguments; stream_names sub_name stream_types stream_parent
# example: create_streams "Main ArtSource Tools" "dev" "mainline" "none"
create_streams()
{
    local sub_name=$2
    local stream_type=$3
    local stream_parent=$4
    local base_parent=$4
    local stream_options="Options:	allsubmit unlocked toparent fromparent mergedown"

    for stream_name in $1; do
        log "INFO" "Processing stream: ${stream_name}"

        parent_view="inherit"

        # If the stream is not a release stream or the parent is the base stream,
        # then allow the merge down.
        if [[ "${stream_type}" != "release" ]] || [[ "${stream_parent}" == "${base_parent}" ]]; then
            stream_options="Options:	allsubmit unlocked toparent fromparent mergedown"
        fi

        # Mainline streams do not have a parent.
        if [[ "$stream_type" == "mainline" ]]; then
            stream_parent="none"
        fi

        # Release streams logic.
        if [[ "$stream_type" == "release" ]]; then
            parent_view="noinherit"

            # Don't allow merge down to the parents.
            stream_options="Options:	allsubmit unlocked notoparent fromparent mergedown"

            # Release stream whose parent _is_ the base parent are allowed to merge down.
            if [[ "${stream_parent}" == "${base_parent}" ]]; then
                stream_options="Options:	allsubmit unlocked toparent fromparent mergedown"
            fi
        fi

        # Update the spec with this streams settings.
        local spec=${STREAM_SPEC//\{\{\{STREAM_NAME\}\}\}/${stream_name}}
        spec=${spec//\{\{\{SUB_NAME\}\}\}/${sub_name}}
        spec=${spec//\{\{\{STREAM_PARENT\}\}\}/${stream_parent}}
        spec=${spec//\{\{\{STREAM_TYPE\}\}\}/${stream_type}}
        spec=${spec//\{\{\{PARENT_VIEW\}\}\}/${parent_view}}

        if ! p4 streams //${PROJECT_NAME}/${sub_name}/... | grep -q "${stream_name}" ; then
            log "INFO" "Stream ${stream_name} does not exist. Creating stream..."
            p4 stream -i << EOF
${spec}
${stream_options}
EOF
            # Stop here if the stream could not be created. 
            if [ $? -ne 0 ]; then
                log "ERROR" "Failed to create stream ${stream_name}."
                exit 1
            fi

            log "INFO" "Stream //${PROJECT_NAME}/${sub_name}/${stream_name} created successfully."
        else
            log "INFO" "Stream ${stream_name} already exists. Skipping stream creation."
        fi

        stream_parent="//${PROJECT_NAME}/${stream_type}/${stream_name}"
    done
}

create_p4_project_group()
{
    if ! p4 groups | grep -q "${PROJECT_NAME}"; then
        log "INFO" "Group ${PROJECT_NAME} does not exist. Creating group..."
        p4 group -i << EOF
${P4_GROUP_SPEC}
EOF
        if [ $? -ne 0 ]; then
            log "ERROR" "Failed to create group ${PROJECT_NAME}."
            exit 1
        fi

        log "INFO" "Group ${PROJECT_NAME} created successfully."
    else
        log "INFO" "Group ${PROJECT_NAME} already exists. Skipping group creation."
    fi
}

give_p4_group_permissions_to_project()
{
    _save_protect_to_file()
    {
        p4 protect -o > p4_protections.tmp
    }

    _is_group_in_protections()
    {
        # Return 0 if the group is in the p4 protections table.
        if grep -qF "${PROTECTIONS}" p4_protections.tmp; then
            return 0
        fi
        return 1
    }

    PROTECTIONS="write group ${PROJECT_NAME} * //${PROJECT_NAME}/..."
    _save_protect_to_file

   if ! _is_group_in_protections; then
        log "INFO" "Adding protections for group ${PROJECT_NAME}..."

        # Add the line to the top of the permissions section.
        # We don't append it to the bottom as the permissions order matters. 
        awk -v protections="${PROTECTIONS}" \
            '/^Protections:/{print; print "\t" protections; next}1' p4_protections.tmp > p4_protections.new.tmp

        p4 protect -i < p4_protections.new.tmp

        _save_protect_to_file

        if ! _is_group_in_protections; then
            log "ERROR" "Failed to add protections for group ${PROJECT_NAME}."
            exit 1
        else
            log "INFO" "Protections for group ${PROJECT_NAME} added successfully."
        fi
    else
        log "INFO" "Protections for group ${PROJECT_NAME} already exists. Skipping group creation."
    fi

    # Remove the temp files. 
    rm p4_protections*.tmp
}


# Check if there are enough arguments otherwise, stop here.
if [ "$#" -ne 2 ]; then
    log "ERROR" "Usage: $0 <project_name> <project_user>"
    exit 1
fi 

# Start the App
log "INFO" "### Starting new P4 project setup script. ###"

# Validate the Perforce installation and super user.
validate_p4_install
validate_logged_in_p4_user

LOGGED_IN_USER=$(p4 login -s | cut -d' ' -f2)
log "INFO" "Using logged in P4 user: ${LOGGED_IN_USER}"

validate_logged_in_p4_users_permissions

# PROJECT DEPOT AND STREAM CREATION
create_p4_depot
create_streams "${MAINLINE_STREAMS}" "dev" "mainline" "none"
create_streams "${RELEASE_STREAMS}" "release" "release" "//${PROJECT_NAME}/dev/Main"

# GROUPS and PERMISSIONS!
create_p4_project_group
give_p4_group_permissions_to_project

log "INFO" "### Finished new P4 project setup script. ###"
