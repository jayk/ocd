#!/usr/bin/env bash

OCD_IMAGE="${OPENCODE_DOCKER_IMAGE:-jayk/ocd:latest}"
# ------------------------------------------------------------
# Resolve project mount
# ------------------------------------------------------------
HOST_PROJECT_DIR="$(pwd -P)"
PROJECT_NAME="$(basename "${HOST_PROJECT_DIR}")"
# CTR_PROJECT_DIR="/opt/ocd_dev/dev/${PROJECT_NAME}"

# ------------------------------------------------------------
# Project configuration
# ------------------------------------------------------------
PROJECT_CONFIG="${HOST_PROJECT_DIR}/ocd.conf"
CONFIG_MOUNTS=()

if [[ -f "${PROJECT_CONFIG}" ]]; then
    echo "Loading project configuration: ${PROJECT_CONFIG}"

    while IFS= read -r CONFIG_LINE || [[ -n "${CONFIG_LINE}" ]]; do
        CONFIG_LINE="${CONFIG_LINE%$'\r'}"

        case "${CONFIG_LINE}" in
            ""|\#*)
                ;;
            OPENCODE_MOUNTS=*)
                CONFIG_MOUNTS+=("${CONFIG_LINE#OPENCODE_MOUNTS=}")
                ;;
            *)
                echo "Unsupported ocd.conf entry: ${CONFIG_LINE}" >&2
                echo "Only OPENCODE_MOUNTS=/path[:/another/path] is supported." >&2
                exit 2
                ;;
        esac
    done < "${PROJECT_CONFIG}"
fi

# ------------------------------------------------------------
# Wrapper arguments
# ------------------------------------------------------------
CMD_ARGS=()
CLI_MOUNTS=()

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -d|--mountdir)
            if [[ "$#" -lt 2 || -z "$2" ]]; then
                echo "${1} requires a directory path." >&2
                exit 2
            fi
            CLI_MOUNTS+=("$2")
            shift 2
            ;;
        --mountdir=*)
            MOUNT_DIR="${1#--mountdir=}"
            if [[ -z "${MOUNT_DIR}" ]]; then
                echo "--mountdir requires a directory path." >&2
                exit 2
            fi
            CLI_MOUNTS+=("${MOUNT_DIR}")
            shift
            ;;
        --)
            CMD_ARGS+=("$@")
            break
            ;;
        *)
            CMD_ARGS+=("$1")
            shift
            ;;
    esac
done

COMMAND_NAME="${CMD_ARGS[0]:-}"

# ------------------------------------------------------------
# Server password
# ------------------------------------------------------------
OPENCODE_SERVER_PASSWORD="${OPENCODE_SERVER_PASSWORD:-}"
case "${COMMAND_NAME}" in
    web|serve)
        if [[ -z "${OPENCODE_SERVER_PASSWORD}" ]]; then
            WORD_LIST="/usr/share/dict/words"
            if [[ -f "${WORD_LIST}" ]]; then
                OPENCODE_SERVER_PASSWORD="$(shuf -n 3 "${WORD_LIST}" | tr -d "'" | tr '\n' '-' | sed 's/-$//')"
            else
                OPENCODE_SERVER_PASSWORD="$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 10)"
            fi
            echo "Securing your opencode service. Password is: ${OPENCODE_SERVER_PASSWORD}"
            # read -r -p "Press Enter to continue..." _
        fi
        ;;
esac
set -euo pipefail

# ------------------------------------------------------------
# Native OpenCode defaults (host-side)
# ------------------------------------------------------------
HOST_HOME="${HOME}"

NATIVE_CONFIG_DIR="${XDG_CONFIG_HOME:-${HOST_HOME}/.config}/opencode"
NATIVE_DATA_DIR="${XDG_DATA_HOME:-${HOST_HOME}/.local/share}/opencode"
NATIVE_AGENTS_DIR="${HOST_HOME}/.agents"

# ------------------------------------------------------------
# Consolidated override (Tier 2)
# ------------------------------------------------------------
HOST_OPENCODE_DIR="${HOST_OPENCODE_DIR:-}"

if [[ -n "${HOST_OPENCODE_DIR}" ]]; then
    CONSOLIDATED_CONFIG_DIR="${HOST_OPENCODE_DIR}/config"
    CONSOLIDATED_DATA_DIR="${HOST_OPENCODE_DIR}/share"
    CONSOLIDATED_AGENTS_DIR="${HOST_OPENCODE_DIR}/agents"
fi

# ------------------------------------------------------------
# Tier 1 explicit overrides (host-side)
# ------------------------------------------------------------
HOST_CONFIG_DIR="${OPENCODE_CONFIG_DIR:-}"
HOST_DATA_DIR="${XDG_DATA_HOME:-}"
HOST_AGENTS_DIR="${OPENCODE_AGENTS_DIR:-}"

# ------------------------------------------------------------
# Resolve final host paths (precedence: Tier 1 → Tier 2 → native)
# ------------------------------------------------------------
FINAL_CONFIG_DIR="$(
    if [[ -n "${HOST_CONFIG_DIR}" ]]; then
        echo "${HOST_CONFIG_DIR}"
    elif [[ -n "${HOST_OPENCODE_DIR}" ]]; then
        echo "${CONSOLIDATED_CONFIG_DIR}"
    else
        echo "${NATIVE_CONFIG_DIR}"
    fi
)"

FINAL_DATA_DIR="$(
    if [[ -n "${HOST_DATA_DIR}" ]]; then
        echo "${HOST_DATA_DIR}/opencode"
    elif [[ -n "${HOST_OPENCODE_DIR}" ]]; then
        echo "${CONSOLIDATED_DATA_DIR}"
    else
        echo "${NATIVE_DATA_DIR}"
    fi
)"

FINAL_AGENTS_DIR="$(
    if [[ -n "${HOST_AGENTS_DIR}" ]]; then
        echo "${HOST_AGENTS_DIR}"
    elif [[ -n "${HOST_OPENCODE_DIR}" ]]; then
        echo "${CONSOLIDATED_AGENTS_DIR}"
    else
        echo "${NATIVE_AGENTS_DIR}"
    fi
)"

# ------------------------------------------------------------
# Ensure host directories exist
# ------------------------------------------------------------
mkdir -p \
    "${FINAL_CONFIG_DIR}" \
    "${FINAL_DATA_DIR}" \
    "${FINAL_AGENTS_DIR}"

# ------------------------------------------------------------
# Container canonical paths
# ------------------------------------------------------------
CTR_CONFIG_DIR="/opt/ocd_dev/.config/opencode"
CTR_DATA_DIR="/opt/ocd_dev/.local/share/opencode"
CTR_AGENTS_DIR="/opt/ocd_dev/.agents"

# ------------------------------------------------------------
# Port mappings (conditional)
# ------------------------------------------------------------
PORT_ARGS=()
if [[ "${COMMAND_NAME}" == auth* ]]; then
    PORT_ARGS+=("-p" "127.0.0.1:1455:1455")
fi

case "${COMMAND_NAME}" in
    web|serve)
        PORT_ARGS+=("-p" "127.0.0.1:4096:4096")
        ;;
esac

if [ ! -z "${OPENCODE_EDITOR:-}" ]; then
    OC_EDITOR="${OPENCODE_EDITOR:-}"
elif [ ! -z "${EDITOR}" ]; then
   OC_EDITOR="${EDITOR}"
else
   OC_EDITOR="nano"
fi

# ------------------------------------------------------------
# Configure web mode arguments
# ------------------------------------------------------------
case "${COMMAND_NAME}" in
    web|serve)
        HAS_HOSTNAME_FLAG=0
        for ARG in "${CMD_ARGS[@]}"; do
            case "${ARG}" in
                --hostname|--hostname=*)
                    HAS_HOSTNAME_FLAG=1
                    break
                    ;;
            esac
        done

        if [[ "${HAS_HOSTNAME_FLAG}" -eq 0 ]]; then
            CMD_ARGS+=("--hostname" "0.0.0.0")
        fi
        ;;
esac

# ------------------------------------------------------------
# Optional extra mounts (host path -> same container path)
# ------------------------------------------------------------
EXTRA_MOUNT_ARGS=()
EXTRA_MOUNT_PATHS=()
declare -A MOUNT_PATH_SEEN=()

add_mount() {
    local mount_path="$1"
    local require_directory="$2"

    if [[ "${mount_path}" != /* ]]; then
        mount_path="${HOST_PROJECT_DIR}/${mount_path}"
    fi
    mount_path="$(realpath -m -- "${mount_path}")"

    if [[ "${require_directory}" == 1 && ! -d "${mount_path}" ]]; then
        echo "--mountdir path is not a directory: ${mount_path}" >&2
        exit 2
    fi

    if [[ -n "${MOUNT_PATH_SEEN[${mount_path}]:-}" ]]; then
        return
    fi

    MOUNT_PATH_SEEN["${mount_path}"]=1
    EXTRA_MOUNT_PATHS+=("${mount_path}")
    EXTRA_MOUNT_ARGS+=("-v" "${mount_path}:${mount_path}:rw")
}

for CONFIG_MOUNT_LIST in "${CONFIG_MOUNTS[@]}"; do
    IFS=':' read -r -a MOUNT_PATHS <<< "${CONFIG_MOUNT_LIST}"
    for MOUNT_PATH in "${MOUNT_PATHS[@]}"; do
        [[ -z "${MOUNT_PATH}" ]] && continue
        add_mount "${MOUNT_PATH}" 0
    done
done

if [[ -n "${OPENCODE_MOUNTS:-}" ]]; then
    IFS=':' read -r -a MOUNT_PATHS <<< "${OPENCODE_MOUNTS}"
    for MOUNT_PATH in "${MOUNT_PATHS[@]}"; do
        [[ -z "${MOUNT_PATH}" ]] && continue
        add_mount "${MOUNT_PATH}" 0
    done
fi

for MOUNT_PATH in "${CLI_MOUNTS[@]}"; do
    add_mount "${MOUNT_PATH}" 1
done

if [[ "${#EXTRA_MOUNT_PATHS[@]}" -gt 0 ]]; then
    echo "Additional mounts:"
    printf '  %s\n' "${EXTRA_MOUNT_PATHS[@]}"
fi

# ------------------------------------------------------------
# Run container
# ------------------------------------------------------------
docker run --rm -it \
    --name "oc-${PROJECT_NAME}-$$" \
    --user 1000:1000 \
    --workdir "${HOST_PROJECT_DIR}" \
    --env "HOME=/opt/ocd_dev" \
    --env "TERM=${TERM:-xterm-256color}" \
    --env "XDG_CONFIG_HOME=/opt/ocd_dev/.config" \
    --env "XDG_DATA_HOME=/opt/ocd_dev/.local/share" \
    --env "OPENCODE_CONFIG_DIR=${CTR_CONFIG_DIR}" \
    --env "OPENCODE_SERVER_PASSWORD=${OPENCODE_SERVER_PASSWORD}" \
    --env "EDITOR=${OC_EDITOR}" \
    "${PORT_ARGS[@]}" \
    -v "${HOST_PROJECT_DIR}:${HOST_PROJECT_DIR}:rw" \
    -v "${FINAL_CONFIG_DIR}:${CTR_CONFIG_DIR}:rw" \
    -v "${FINAL_DATA_DIR}:${CTR_DATA_DIR}:rw" \
    -v "${FINAL_AGENTS_DIR}:${CTR_AGENTS_DIR}:rw" \
    "${EXTRA_MOUNT_ARGS[@]}" \
    --security-opt no-new-privileges:true \
    --cap-drop ALL \
    --pids-limit 512 \
    "${OCD_IMAGE}" \
    /usr/local/bin/opencode-entrypoint \
    "${CMD_ARGS[@]}"
