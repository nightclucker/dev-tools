#!/usr/bin/env bash
# Bootstraps a new Perforce (P4) project: depot, mainline/release streams,
# a project group, and the protections entry tying them together.
# See p4-setup-script-design.md for the design this implements.
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
LOGGER_TAG="p4-project-bootstrap"
STREAM_DEPTH=2
DRY_RUN=0

PROJECT_NAME=""
USERS_CSV=""
OWNER_USER=""
declare -a USER_LIST=()

usage()
{
    cat <<EOF
Usage: ${SCRIPT_NAME} [-n|--dry-run] <project_name> <user1,user2,...>

  project_name   Name of the new project. Used as the depot name, group
                 name, and protections-table entry.
  user1,user2    Comma-separated list of P4 usernames to add to the
                 project group. The first user is treated as the owner.

Options:
  -n, --dry-run  Show what would be created without making any changes.
  -h, --help     Show this help text.

Example:
  ${SCRIPT_NAME} MyGame alice,bob,carol
EOF
}

_log()
{
    local level="$1"
    shift
    local message="$*"
    local ts
    ts="$(date '+%Y-%m-%d %H:%M:%S')"

    echo "[${ts}] [${level}] ${message}"
    if command -v logger > /dev/null 2>&1; then
        logger -t "${LOGGER_TAG}" -- "[${level}] ${message}"
    fi
}

log_info()  { _log "INFO"  "$@"; }
log_warn()  { _log "WARN"  "$@"; }
log_error() { _log "ERROR" "$@" >&2; }

parse_args()
{
    local positional=()

    while [ "$#" -gt 0 ]; do
        case "$1" in
            -n|--dry-run)
                DRY_RUN=1
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            --)
                shift
                positional+=("$@")
                break
                ;;
            -*)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
            *)
                positional+=("$1")
                shift
                ;;
        esac
    done

    if [ "${#positional[@]}" -ne 2 ]; then
        usage
        exit 1
    fi

    PROJECT_NAME="${positional[0]}"
    USERS_CSV="${positional[1]}"
}

validate_project_name()
{
    if ! [[ "${PROJECT_NAME}" =~ ^[A-Za-z][A-Za-z0-9_-]{0,63}$ ]]; then
        log_error "Invalid project name '${PROJECT_NAME}'. Must start with a letter and contain only letters, numbers, '_' or '-' (max 64 chars)."
        exit 1
    fi
}

validate_users_list()
{
    local raw_user seen_users=","

    IFS=',' read -ra raw_users <<< "${USERS_CSV}"

    for raw_user in "${raw_users[@]}"; do
        # Trim leading/trailing whitespace.
        local trimmed_user="${raw_user#"${raw_user%%[![:space:]]*}"}"
        trimmed_user="${trimmed_user%"${trimmed_user##*[![:space:]]}"}"

        if [ -z "${trimmed_user}" ]; then
            log_error "User list '${USERS_CSV}' contains an empty entry."
            exit 1
        fi

        if [[ "${seen_users}" == *",${trimmed_user},"* ]]; then
            log_error "User list '${USERS_CSV}' contains duplicate entry '${trimmed_user}'."
            exit 1
        fi
        seen_users="${seen_users}${trimmed_user},"

        USER_LIST+=("${trimmed_user}")
    done

    if [ "${#USER_LIST[@]}" -eq 0 ]; then
        log_error "At least one P4 user must be provided."
        exit 1
    fi

    OWNER_USER="${USER_LIST[0]}"

    for trimmed_user in "${USER_LIST[@]}"; do
        if ! p4 user -o "${trimmed_user}" 2>/dev/null | grep -q "^User:"; then
            log_warn "P4 user '${trimmed_user}' could not be resolved. Continuing anyway."
        fi
    done
}

check_prerequisites()
{
    if ! command -v p4 > /dev/null 2>&1; then
        log_error "Perforce CLI tools (p4) are not installed or not in the PATH."
        exit 1
    fi

    if ! p4 login -s > /dev/null 2>&1; then
        log_error "p4 user is not logged in."
        exit 1
    fi

    LOGGED_IN_USER="$(p4 login -s | cut -d' ' -f2)"
    log_info "Using logged in P4 user: ${LOGGED_IN_USER}"

    if ! p4 groups "${LOGGED_IN_USER}" | grep -qx "Super"; then
        log_error "Logged in user does not have permission to create depots, streams, or groups!"
        exit 1
    fi
    log_info "Logged in user has permission to create depots, streams, and groups."
}

depot_exists()
{
    [ -n "$(p4 depots -e "${PROJECT_NAME}" 2>/dev/null)" ]
}

stream_exists()
{
    local stream_path="$1"
    [ -n "$(p4 streams -F "Stream=${stream_path}" 2>/dev/null)" ]
}

group_exists()
{
    p4 groups 2>/dev/null | grep -qx "${PROJECT_NAME}"
}

protection_exists()
{
    p4 protect -o 2>/dev/null | grep -qF "group ${PROJECT_NAME} * //${PROJECT_NAME}/..."
}

create_depot()
{
    if depot_exists; then
        log_info "Depot ${PROJECT_NAME} already exists. Skipping depot creation."
        return
    fi

    local description="Created by ${SCRIPT_NAME} on $(date -u '+%Y-%m-%dT%H:%M:%SZ') for project ${PROJECT_NAME}."

    if [ "${DRY_RUN}" -eq 1 ]; then
        log_info "[DRY-RUN] Would create depot ${PROJECT_NAME} (Type: stream, StreamDepth: ${STREAM_DEPTH})."
        return
    fi

    log_info "Depot ${PROJECT_NAME} does not exist. Creating depot..."
    p4 depot -i <<EOF
Depot: ${PROJECT_NAME}
Owner: ${OWNER_USER}
Type: stream
Description: ${description}
StreamDepth: ${STREAM_DEPTH}
Map: ${PROJECT_NAME}/...
EOF

    log_info "Depot //${PROJECT_NAME}/... created successfully."
}

create_mainline_stream()
{
    local name="$1"
    local stream_path="//${PROJECT_NAME}/dev/${name}"

    if stream_exists "${stream_path}"; then
        log_info "Stream ${stream_path} already exists. Skipping stream creation."
        return
    fi

    local description="Created by ${SCRIPT_NAME} on $(date -u '+%Y-%m-%dT%H:%M:%SZ') for project ${PROJECT_NAME}."

    if [ "${DRY_RUN}" -eq 1 ]; then
        log_info "[DRY-RUN] Would create mainline stream ${stream_path}."
        return
    fi

    log_info "Stream ${stream_path} does not exist. Creating stream..."
    p4 stream -i <<EOF
Stream: ${stream_path}
Owner: ${OWNER_USER}
Name: ${name}
Type: mainline
Description: ${description}
Parent: none
ParentView: inherit
Paths: share ...
Options: allsubmit unlocked toparent fromparent mergedown
EOF

    log_info "Stream ${stream_path} created successfully."
}

create_release_stream()
{
    local name="$1"
    local parent="$2"
    local allow_mergedown="$3"
    local stream_path="//${PROJECT_NAME}/release/${name}"

    if stream_exists "${stream_path}"; then
        log_info "Stream ${stream_path} already exists. Skipping stream creation."
        return
    fi

    local description="Created by ${SCRIPT_NAME} on $(date -u '+%Y-%m-%dT%H:%M:%SZ') for project ${PROJECT_NAME}."
    local parent_view stream_options

    if [ "${allow_mergedown}" = "yes" ]; then
        parent_view="inherit"
        stream_options="Options: allsubmit unlocked toparent fromparent mergedown"
    else
        parent_view="noinherit"
        stream_options="Options: allsubmit unlocked notoparent fromparent mergedown"
    fi

    if [ "${DRY_RUN}" -eq 1 ]; then
        log_info "[DRY-RUN] Would create release stream ${stream_path} (parent: ${parent}, mergedown to parent: ${allow_mergedown})."
        return
    fi

    log_info "Stream ${stream_path} does not exist. Creating stream..."
    p4 stream -i <<EOF
Stream: ${stream_path}
Owner: ${OWNER_USER}
Name: ${name}
Type: release
Description: ${description}
Parent: ${parent}
ParentView: ${parent_view}
Paths: share ...
${stream_options}
EOF

    log_info "Stream ${stream_path} created successfully."
}

create_group()
{
    if group_exists; then
        log_info "Group ${PROJECT_NAME} already exists. Skipping group creation."
        return
    fi

    local description="Created by ${SCRIPT_NAME} on $(date -u '+%Y-%m-%dT%H:%M:%SZ') for project ${PROJECT_NAME}."

    if [ "${DRY_RUN}" -eq 1 ]; then
        log_info "[DRY-RUN] Would create group ${PROJECT_NAME} with users: ${USER_LIST[*]}."
        return
    fi

    log_info "Group ${PROJECT_NAME} does not exist. Creating group..."
    {
        echo "Group: ${PROJECT_NAME}"
        echo "Description: ${description}"
        echo "Owners:"
        echo "	${OWNER_USER}"
        echo "Users:"
        for user in "${USER_LIST[@]}"; do
            echo "	${user}"
        done
    } | p4 group -i

    log_info "Group ${PROJECT_NAME} created successfully."
}

update_group_members()
{
    if ! group_exists; then
        return
    fi

    local existing_users
    existing_users="$(p4 group -o "${PROJECT_NAME}" | awk '/^Users:/{f=1;next} /^[A-Za-z]+:/{f=0} f{print $1}')"

    local -a missing_users=()
    local user
    for user in "${USER_LIST[@]}"; do
        if ! grep -qx "${user}" <<< "${existing_users}"; then
            missing_users+=("${user}")
        fi
    done

    if [ "${#missing_users[@]}" -eq 0 ]; then
        log_info "Group ${PROJECT_NAME} already contains all requested users. Skipping."
        return
    fi

    if [ "${DRY_RUN}" -eq 1 ]; then
        log_info "[DRY-RUN] Would add missing users to group ${PROJECT_NAME}: ${missing_users[*]}."
        return
    fi

    log_info "Adding missing users to group ${PROJECT_NAME}: ${missing_users[*]}"
    {
        p4 group -o "${PROJECT_NAME}"
        for user in "${missing_users[@]}"; do
            echo "	${user}"
        done
    } | p4 group -i

    log_info "Group ${PROJECT_NAME} updated successfully."
}

update_protections_table()
{
    if protection_exists; then
        log_info "Protections for group ${PROJECT_NAME} already exist. Skipping."
        return
    fi

    local new_rule="	write group ${PROJECT_NAME} * //${PROJECT_NAME}/..."

    if [ "${DRY_RUN}" -eq 1 ]; then
        log_info "[DRY-RUN] Would add protections rule:${new_rule}"
        return
    fi

    log_info "Adding protections for group ${PROJECT_NAME}..."

    local protect_file
    protect_file="$(mktemp)"

    p4 protect -o > "${protect_file}"

    # Insert the new rule right after the Protections: header, ahead of any
    # existing rules, so it is evaluated before more specific/narrower rules
    # further down the table (protection order matters in p4).
    awk -v rule="${new_rule}" \
        '/^Protections:/{print; print rule; next}1' "${protect_file}" | p4 protect -i

    rm -f "${protect_file}"

    if ! protection_exists; then
        log_error "Failed to add protections for group ${PROJECT_NAME}."
        exit 1
    fi

    log_info "Protections for group ${PROJECT_NAME} added successfully."
}

main()
{
    parse_args "$@"
    validate_project_name
    validate_users_list

    log_info "### Starting ${SCRIPT_NAME}. ###"
    if [ "${DRY_RUN}" -eq 1 ]; then
        log_info "Dry-run mode enabled. No changes will be made."
    fi

    check_prerequisites

    create_depot
    create_mainline_stream "Main"
    create_mainline_stream "ArtSource"
    create_mainline_stream "Tools"
    create_release_stream "Staging" "//${PROJECT_NAME}/dev/Main" "yes"
    create_release_stream "Production" "//${PROJECT_NAME}/release/Staging" "no"
    create_release_stream "Live" "//${PROJECT_NAME}/release/Production" "no"

    create_group
    update_group_members
    update_protections_table

    log_info "### Finished ${SCRIPT_NAME}. ###"
}

main "$@"
