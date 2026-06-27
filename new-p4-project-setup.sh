#!/bin/bash
# This script sets up a new P4 project by creating the necessary directory structure and files.
# Need to run this script with the project name, a valid p4 user name.


LOGGER_NAME="p4-project-setup"
log()
{
    local level="$1"
    shift
    local message="$*"

    echo "[${level}] ${message}"
    logger -t "${LOGGER_NAME}" "[${level}] ${message}"
}

log "INFO" "### Starting new P4 project setup script. ###"

if [ "$#" -ne 2 ]; then
    log "ERROR" "Usage: $0 <project_name> <project_user>"
    exit 1
fi 

PROJECT_NAME=$1
PROJECT_USERS=$2
PROJECT_REQUESTER=${PROJECT_USERS%%,*}  # Get the first user from the comma-separated list
MAINLINE_STREAMS="Main ArtSource Tools"
RELEASE_STREAMS="Staging Production Live"
STREAM_DEPTH=2
DEPOT_SPEC="""
Depot: ${PROJECT_NAME}
Owner: ${PROJECT_REQUESTER}
Type: stream
Description: Project depot automatically created on $(date).  Creation requested by ${PROJECT_REQUESTER}.
StreamDepth: ${STREAM_DEPTH}
Map: ${PROJECT_NAME}/...
"""
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

# P4 VALIDATION
# Use the Perforce CLI tools exists
if [ ! -x "$(which p4)" ]; then
    log "ERROR" "Perforce CLI tools (p4) are not installed or not in the PATH."
    exit 1
fi

# Check if p4 user is logged in.
if ! p4 login -s > /dev/null 2>&1; then
    log "ERROR" "p4 user is not logged in."
    exit 1
fi

# Check if p4 user has permission to create depots, streams, and groups.
LOGGED_IN_USER=$(p4 login -s | cut -d' ' -f2)
log "INFO" "Using logged in P4 user: ${LOGGED_IN_USER}"

if ! p4 group -o "Super" | grep "$LOGGED_IN_USER" > /dev/null 2>&1; then
    log "ERROR" "Logged in user does not have permission to create depots, streams, or groups!"
    exit 1
fi
log "INFO" "Logged in user has permission to create depots, streams, and groups."

# PROJECT DEPOT AND STREAM CREATION
# check if the project depot exists, skip depot creation
if ! p4 depots -e "${PROJECT_NAME}" | grep "${PROJECT_NAME}" > /dev/null 2>&1; then
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

for stream in ${MAINLINE_STREAMS}; do
    log "INFO" "Processing stream: ${stream}"
    STREAM_NAME="${stream}"
    SUB_NAME="dev"
    STREAM_TYPE="mainline"
    STREAM_PARENT="none"
    PARENT_VIEW="inherit"
    spec=${STREAM_SPEC//\{\{\{STREAM_NAME\}\}\}/${STREAM_NAME}}
    spec=${spec//\{\{\{SUB_NAME\}\}\}/${SUB_NAME}}
    spec=${spec//\{\{\{STREAM_PARENT\}\}\}/${STREAM_PARENT}}
    spec=${spec//\{\{\{STREAM_TYPE\}\}\}/${STREAM_TYPE}}
    spec=${spec//\{\{\{PARENT_VIEW\}\}\}/${PARENT_VIEW}}

    if ! p4 streams //${PROJECT_NAME}/${SUB_NAME}/... | grep -q "${STREAM_NAME}" ; then
        log "INFO" "Stream ${STREAM_NAME} does not exist. Creating stream..."
        p4 stream -i << EOF
${spec}
EOF

    if [ $? -ne 0 ]; then
        log "ERROR" "Failed to create stream ${STREAM_NAME}."
        exit 1
    fi

        log "INFO" "Stream //${PROJECT_NAME}/${SUB_NAME}/${STREAM_NAME} created successfully."
    else
        log "INFO" "Stream ${STREAM_NAME} already exists. Skipping stream creation."
    fi
done

PREVIOUS_PARENT="//${PROJECT_NAME}/dev/Main"
OPTIONS="Options:	allsubmit unlocked toparent fromparent mergedown"
echo $PREVIOUS_PARENT
for stream in ${RELEASE_STREAMS}; do
    log "INFO" "Processing stream: ${stream}"
    STREAM_NAME="${stream}"
    SUB_NAME="release"
    STREAM_TYPE="release"
    STREAM_PARENT="${PREVIOUS_PARENT}"
    PARENT_VIEW="inherit"
    spec=${STREAM_SPEC//\{\{\{STREAM_NAME\}\}\}/${STREAM_NAME}}
    spec=${spec//\{\{\{SUB_NAME\}\}\}/${SUB_NAME}}
    spec=${spec//\{\{\{STREAM_PARENT\}\}\}/${STREAM_PARENT}}
    spec=${spec//\{\{\{STREAM_TYPE\}\}\}/${STREAM_TYPE}}
    spec=${spec//\{\{\{PARENT_VIEW\}\}\}/${PARENT_VIEW}}

    if ! p4 streams //${PROJECT_NAME}/${SUB_NAME}/... | grep -q "${STREAM_NAME}" ; then
        log "INFO" "Stream ${STREAM_NAME} does not exist. Creating stream..."
        p4 stream -i << EOF
${spec}
${OPTIONS}
EOF
    if [ $? -ne 0 ]; then
        log "ERROR" "Failed to create stream ${STREAM_NAME}."
        exit 1
    fi

        log "INFO" "Stream //${PROJECT_NAME}/${SUB_NAME}/${STREAM_NAME} created successfully."
    else
        log "INFO" "Stream ${STREAM_NAME} already exists. Skipping stream creation."
    fi

    PREVIOUS_PARENT="//${PROJECT_NAME}/release/${STREAM_NAME}"
    OPTIONS="Options:	allsubmit unlocked notoparent fromparent mergedown"
done

# GROUPS and PERMISSIONS!
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

if 

log "INFO" "### Finished new P4 project setup script. ###"