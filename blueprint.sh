#!/usr/bin/env bash
#
# ╔══════════════════════════════════════════════════════════════════════╗
# ║                    ROOTSUNNYLAB • BLUEPRINT                        ║
# ║              Pterodactyl Blueprint Installer                       ║
# ║                                                                    ║
# ║  A polished, distro-aware installer for Blueprint Framework.       ║
# ║  Source guidance: https://blueprint.zip/guides/admin/install      ║
# ╚══════════════════════════════════════════════════════════════════════╝
#
# ROOTSUNNYLAB watermark — Pterodactyl Blueprint Installer
#
# Supported package-manager families:
#   Debian/Ubuntu (apt), Fedora/RHEL (dnf/yum), Arch (pacman),
#   openSUSE (zypper), Alpine (apk).
#
# NOTE: Blueprint's own runtime/support matrix can vary by release.
# This installer detects the host distribution and installs the common
# prerequisites; it does not claim that every Blueprint release supports
# every Linux distribution.

set -Eeuo pipefail
IFS=$'\n\t'

VERSION="1.0.0"
PTERODACTYL_DIRECTORY="${PTERODACTYL_DIRECTORY:-/var/www/pterodactyl}"
BLUEPRINT_RELEASE_URL="https://github.com/BlueprintFramework/framework/releases/latest/download/release.zip"
NODE_MAJOR="22"

# ---------------------------------------------------------------------------
# Beautiful terminal UI — ROOTSUNNYLAB watermark
# ---------------------------------------------------------------------------

if [[ -t 1 ]]; then
    BOLD='\033[1m'
    DIM='\033[2m'
    RESET='\033[0m'
    WHITE='\033[97m'
    GRAY='\033[90m'
    GREEN='\033[92m'
    YELLOW='\033[93m'
    RED='\033[91m'
    CYAN='\033[96m'
else
    BOLD=''; DIM=''; RESET=''; WHITE=''; GRAY=''; GREEN=''; YELLOW=''; RED=''; CYAN=''
fi

cleanup() {
    printf '\n%sROOTSUNNYLAB%s %sBlueprint installer finished.%s\n' "$BOLD" "$RESET" "$DIM" "$RESET" || true
}
trap cleanup EXIT

fail() {
    printf '\n%s✕ ERROR:%s %s\n' "$RED" "$RESET" "$*" >&2
    exit 1
}

info() {
    printf '%s│%s %s\n' "$GRAY" "$RESET" "$*"
}

step() {
    printf '\n%s◆%s %s%s%s\n' "$WHITE" "$RESET" "$BOLD" "$*" "$RESET"
}

ok() {
    printf '%s✓%s %s\n' "$GREEN" "$RESET" "$*"
}

warn() {
    printf '%s!%s %s\n' "$YELLOW" "$RESET" "$*"
}

run() {
    local label="$1"
    shift
    printf '%s  %s%s%s' "$GRAY" "$label" "$RESET" >&2
    local spin='|/-\\'
    local i=0
    "$@" >/tmp/rootsunnylab-blueprint.$$ 2>&1 &
    local pid=$!
    while kill -0 "$pid" 2>/dev/null; do
        printf '\r%s  %s %s%s%s' "$GRAY" "$spin" "\b" "${spin:i%4:1}" "$RESET" >&2
        i=$((i + 1))
        sleep 0.08
    done
    if wait "$pid"; then
        printf '\r%s  ✓%s %s\n' "$GREEN" "$RESET" "$label" >&2
    else
        printf '\r%s  ✕%s %s\n' "$RED" "$RESET" "$label" >&2
        cat /tmp/rootsunnylab-blueprint.$$ >&2 || true
        rm -f /tmp/rootsunnylab-blueprint.$$
        return 1
    fi
    rm -f /tmp/rootsunnylab-blueprint.$$
}

command_exists() { command -v "$1" >/dev/null 2>&1; }

as_root() {
    if [[ "${EUID}" -eq 0 ]]; then
        "$@"
    else
        sudo "$@"
    fi
}

# ---------------------------------------------------------------------------
# Header
# ---------------------------------------------------------------------------

clear 2>/dev/null || true
cat <<'EOF'

██████╗  ██████╗  ██████╗ ████████╗███████╗██╗   ██╗███╗   ██╗██╗  ██╗██╗   ██╗
██╔══██╗██╔═══██╗██╔═══██╗╚══██╔══╝██╔════╝██║   ██║████╗  ██║██║  ██║╚██╗ ██╔╝
██████╔╝██║   ██║██║   ██║   ██║   ███████╗██║   ██║██╔██╗ ██║███████║ ╚████╔╝
██╔══██╗██║   ██║██║   ██║   ██║   ╚════██║██║   ██║██║╚██╗██║██╔══██║  ╚██╔╝
██║  ██║╚██████╔╝╚██████╔╝   ██║   ███████║╚██████╔╝██║ ╚████║██║  ██║   ██║
╚═╝  ╚═╝ ╚═════╝  ╚═════╝    ╚═╝   ╚══════╝ ╚═════╝ ╚═╝  ╚═══╝╚═╝  ╚═╝   ╚═╝

                    P T E R O D A C T Y L   B L U E P R I N T
                         ROOTSUNNYLAB • INSTALLER
EOF
printf '\n%s%sVersion %s%s  •  %sAnimated • Distro-aware • Idempotent%s\n\n' "$DIM" "$WHITE" "$VERSION" "$RESET" "$GRAY" "$RESET"

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------

step "Preflight checks"

[[ "$(uname -s)" == "Linux" ]] || fail "This installer supports Linux hosts only."
command_exists sudo || [[ "${EUID}" -eq 0 ]] || fail "sudo is required when running as a non-root user."

if [[ ! -d "$PTERODACTYL_DIRECTORY" ]]; then
    warn "Pterodactyl directory does not exist: $PTERODACTYL_DIRECTORY"
    read -r -p "Create it and continue? [y/N] " answer
    [[ "$answer" =~ ^[Yy]$ ]] || fail "Cancelled."
    as_root mkdir -p "$PTERODACTYL_DIRECTORY"
fi

if [[ ! -w "$PTERODACTYL_DIRECTORY" && "${EUID}" -ne 0 ]]; then
    info "The installer will use sudo where required."
fi

# ---------------------------------------------------------------------------
# Detect distribution/package manager
# ---------------------------------------------------------------------------

step "Detecting Linux distribution"

OS_ID="unknown"
OS_LIKE=""
if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    OS_ID="${ID:-unknown}"
    OS_LIKE="${ID_LIKE:-}"
fi

PKG=""
if command_exists apt-get; then
    PKG="apt"
elif command_exists dnf; then
    PKG="dnf"
elif command_exists yum; then
    PKG="yum"
elif command_exists pacman; then
    PKG="pacman"
elif command_exists zypper; then
    PKG="zypper"
elif command_exists apk; then
    PKG="apk"
fi

info "Distribution: ${OS_ID}"
info "Package manager: ${PKG:-unknown}"
[[ -n "$PKG" ]] || fail "No supported package manager detected."

# ---------------------------------------------------------------------------
# Package installation helpers
# ---------------------------------------------------------------------------

install_packages() {
    case "$PKG" in
        apt)
            as_root apt-get update -y
            as_root apt-get install -y ca-certificates curl git gnupg unzip wget zip
            ;;
        dnf)
            as_root dnf install -y ca-certificates curl git gnupg2 unzip wget zip
            ;;
        yum)
            as_root yum install -y ca-certificates curl git gnupg2 unzip wget zip
            ;;
        pacman)
            as_root pacman -Sy --noconfirm ca-certificates curl git gnupg unzip wget zip
            ;;
        zypper)
            as_root zypper --non-interactive refresh
            as_root zypper --non-interactive install ca-certificates curl git gpg2 unzip wget zip
            ;;
        apk)
            as_root apk add --no-cache ca-certificates curl git gnupg unzip wget zip bash
            ;;
    esac
}

install_packages_dnf_family() {
    case "$PKG" in
        dnf) as_root dnf install -y "$@" ;;
        yum) as_root yum install -y "$@" ;;
        pacman) as_root pacman -S --noconfirm "$@" ;;
        zypper) as_root zypper --non-interactive install "$@" ;;
        apk) as_root apk add --no-cache "$@" ;;
        apt) as_root apt-get install -y "$@" ;;
    esac
}

# ---------------------------------------------------------------------------
# Dependencies
# ---------------------------------------------------------------------------

step "Installing system dependencies"
run "Installing curl, git, unzip, wget and zip" install_packages
ok "Base dependencies ready."

# ---------------------------------------------------------------------------
# Node.js 22
# ---------------------------------------------------------------------------

step "Preparing Node.js ${NODE_MAJOR}"

NODE_OK=0
if command_exists node; then
    NODE_VERSION="$(node --version 2>/dev/null || true)"
    if [[ "$NODE_VERSION" =~ ^v22\. ]]; then
        NODE_OK=1
        ok "Node.js ${NODE_VERSION} already installed."
    else
        warn "Detected ${NODE_VERSION:-unknown}; Blueprint installer will use Node.js ${NODE_MAJOR}."
    fi
fi

if [[ "$NODE_OK" -eq 0 ]]; then
    case "$PKG" in
        apt)
            run "Installing NodeSource signing key" bash -c '
                set -e
                mkdir -p /tmp/rootsunnylab-node
                curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key -o /tmp/rootsunnylab-node/nodesource.asc
                gpg --dearmor < /tmp/rootsunnylab-node/nodesource.asc > /tmp/rootsunnylab-node/nodesource.gpg
                install -d -m 0755 /etc/apt/keyrings
                install -m 0644 /tmp/rootsunnylab-node/nodesource.gpg /etc/apt/keyrings/nodesource.gpg
            '
            as_root bash -c 'echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" > /etc/apt/sources.list.d/nodesource.list'
            as_root apt-get update -y
            run "Installing Node.js ${NODE_MAJOR}" as_root apt-get install -y nodejs
            ;;
        dnf|yum)
            run "Installing Node.js ${NODE_MAJOR}" bash -c "curl -fsSL https://rpm.nodesource.com/setup_${NODE_MAJOR}.x | $( [[ \"$EUID\" -eq 0 ]] && printf '' || printf 'sudo ' ) -E bash - && $( [[ \"$PKG\" == dnf ]] && printf 'sudo dnf install -y nodejs' || printf 'sudo yum install -y nodejs' )"
            ;;
        pacman)
            warn "Arch provides rolling Node.js packages; installing the repository nodejs package."
            run "Installing Node.js" install_packages_dnf_family nodejs npm
            ;;
        zypper)
            run "Installing Node.js" install_packages_dnf_family nodejs npm
            ;;
        apk)
            run "Installing Node.js" install_packages_dnf_family nodejs npm
            ;;
        *)
            fail "Unable to install Node.js automatically on this host."
            ;;
    esac
fi

command_exists node || fail "Node.js installation failed."
command_exists npm || fail "npm installation failed."

NODE_VERSION="$(node --version)"
NPM_VERSION="$(npm --version)"
info "Node.js: ${NODE_VERSION}"
info "npm: ${NPM_VERSION}"

# ---------------------------------------------------------------------------
# Yarn
# ---------------------------------------------------------------------------

step "Preparing Yarn"
if command_exists yarn; then
    ok "Yarn is already installed: $(yarn --version 2>/dev/null || echo unknown)"
else
    run "Installing Yarn globally" npm install -g yarn
fi
command_exists yarn || fail "Yarn installation failed."

# ---------------------------------------------------------------------------
# Download Blueprint release
# ---------------------------------------------------------------------------

step "Downloading Blueprint"

TMP_DIR="$(mktemp -d -t rootsunnylab-blueprint.XXXXXX)"
RELEASE_ZIP="${TMP_DIR}/release.zip"
trap 'rm -rf "$TMP_DIR"' EXIT

run "Downloading latest Blueprint release" curl -fL --retry 3 --retry-delay 1 "$BLUEPRINT_RELEASE_URL" -o "$RELEASE_ZIP"
[[ -s "$RELEASE_ZIP" ]] || fail "Blueprint release archive is empty."

# ---------------------------------------------------------------------------
# Install/extract Blueprint
# ---------------------------------------------------------------------------

step "Installing Blueprint into Pterodactyl"

run "Extracting Blueprint release" as_root unzip -o "$RELEASE_ZIP" -d "$PTERODACTYL_DIRECTORY"

# ---------------------------------------------------------------------------
# Configure .blueprintrc
# ---------------------------------------------------------------------------

step "Configuring Blueprint"

BLUEPRINT_RC="$PTERODACTYL_DIRECTORY/.blueprintrc"
WEBUSER="${WEBUSER:-www-data}"
OWNERSHIP="${OWNERSHIP:-www-data:www-data}"
USERSHELL="${USERSHELL:-/bin/bash}"

# If the requested default web user does not exist, try common alternatives.
if ! id "$WEBUSER" >/dev/null 2>&1; then
    for candidate in nginx apache www-data; do
        if id "$candidate" >/dev/null 2>&1; then
            WEBUSER="$candidate"
            OWNERSHIP="${candidate}:${candidate}"
            break
        fi
    done
fi

run "Writing ${BLUEPRINT_RC}" bash -c "printf '%s\\n' 'WEBUSER=\"${WEBUSER}\";' 'OWNERSHIP=\"${OWNERSHIP}\";' 'USERSHELL=\"${USERSHELL}\";' | $( [[ \"$EUID\" -eq 0 ]] && printf '' || printf 'sudo ' ) tee '$BLUEPRINT_RC' >/dev/null"

# ---------------------------------------------------------------------------
# Install JS dependencies in Pterodactyl directory
# ---------------------------------------------------------------------------

step "Installing Pterodactyl dependencies"
cd "$PTERODACTYL_DIRECTORY"

run "Running yarn install" yarn install

# ---------------------------------------------------------------------------
# Ownership + executable bit
# ---------------------------------------------------------------------------

step "Finalizing installation"

if id "$WEBUSER" >/dev/null 2>&1; then
    run "Applying Pterodactyl ownership" as_root chown -R "$OWNERSHIP" "$PTERODACTYL_DIRECTORY"
else
    warn "Web user '${WEBUSER}' was not found; ownership was left unchanged."
fi

if [[ -f "$PTERODACTYL_DIRECTORY/blueprint.sh" ]]; then
    run "Making blueprint.sh executable" as_root chmod +x "$PTERODACTYL_DIRECTORY/blueprint.sh"
else
    warn "Blueprint release did not contain blueprint.sh at the expected path."
fi

# ---------------------------------------------------------------------------
# Completion
# ---------------------------------------------------------------------------

cat <<EOF

${GREEN}╭──────────────────────────────────────────────────────────────╮${RESET}
${GREEN}│${RESET}  ${BOLD}ROOTSUNNYLAB • BLUEPRINT INSTALL COMPLETE${RESET}              ${GREEN}│${RESET}
${GREEN}├──────────────────────────────────────────────────────────────┤${RESET}
${GREEN}│${RESET}  Pterodactyl: ${PTERODACTYL_DIRECTORY}
${GREEN}│${RESET}  Node.js:     ${NODE_VERSION}
${GREEN}│${RESET}  Yarn:        $(yarn --version 2>/dev/null || echo installed)
${GREEN}│${RESET}  Web user:    ${WEBUSER}
${GREEN}│${RESET}  Config:      ${BLUEPRINT_RC}
${GREEN}│${RESET}  Watermark:   ROOTSUNNYLAB
${GREEN}╰──────────────────────────────────────────────────────────────╯${RESET}

${DIM}Blueprint source:${RESET} ${BLUEPRINT_RELEASE_URL}
${DIM}If the release provides a different supported runtime matrix, follow that
release's official Blueprint documentation before deploying to production.${RESET}

${WHITE}Enjoy your Pterodactyl Blueprint setup. — ROOTSUNNYLAB${RESET}

EOF
