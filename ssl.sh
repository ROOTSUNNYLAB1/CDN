#!/usr/bin/env bash
#
# ssl.sh — Let's Encrypt SSL Certificate Provisioning Utility
#
# Obtains an SSL/TLS certificate from Let's Encrypt using Certbot's manual
# DNS-01 challenge. Designed for Ubuntu/Debian systems.
#
# Usage:
#   sudo bash ssl.sh
#
# -----------------------------------------------------------------------------

set -uo pipefail

SCRIPT_VERSION="1.0.0"
STEP_TOTAL=7

# =============================================================================
# TERMINAL CAPABILITIES & COLOR PALETTE
# (blue / white / gray / green / yellow / red only — no neon, no flashing)
# =============================================================================

if [[ -t 1 ]] && command -v tput &>/dev/null; then
  NCOLORS=$(tput colors 2>/dev/null || echo 0)
else
  NCOLORS=0
fi

if [[ "$NCOLORS" -ge 8 ]]; then
  BOLD=$(tput bold)
  DIM=$(tput dim)
  RESET=$(tput sgr0)
  BLUE=$(tput setaf 4)
  WHITE=$(tput setaf 7)
  GREEN=$(tput setaf 2)
  YELLOW=$(tput setaf 3)
  RED=$(tput setaf 1)
  if [[ "$NCOLORS" -ge 16 ]]; then
    GRAY=$(tput setaf 8)
  else
    GRAY="$DIM"
  fi
else
  BOLD=""; DIM=""; RESET=""; BLUE=""; WHITE=""; GRAY=""; GREEN=""; YELLOW=""; RED=""
fi

IS_TTY=0
[[ -t 1 ]] && IS_TTY=1

# =============================================================================
# RESPONSIVE LAYOUT WIDTH
# =============================================================================

TERM_COLS=$(tput cols 2>/dev/null || echo 80)
TERM_COLS=${TERM_COLS:-80}

if   (( TERM_COLS >= 84 )); then INNER=76
elif (( TERM_COLS >= 60 )); then INNER=$(( TERM_COLS - 6 ))
else                              INNER=50
fi
CONTENT_W=$(( INNER - 2 ))

# =============================================================================
# LOW-LEVEL RENDERING HELPERS
# =============================================================================

# Print N repetitions of a (possibly multi-byte) character.
# Uses printf's format-reuse mechanism rather than `tr`, since `tr` operates
# byte-by-byte and corrupts multi-byte UTF-8 characters on systems that are
# not running a UTF-8 locale (very common on minimal Ubuntu/Debian VPS images).
rule() {
  local ch="$1" n="$INNER" out="" i
  for (( i = 0; i < n; i++ )); do
    out+="$ch"
  done
  printf '%s' "$out"
}

# Strip ANSI escape sequences so padding math counts only visible characters.
strip_ansi() {
  printf '%s' "$1" | sed -E 's/\x1b\[[0-9;]*[a-zA-Z]//g'
}

# Character-accurate length count that does NOT depend on the system locale.
# bash's ${#s} counts bytes under the C/POSIX locale (the default on many
# minimal servers) but counts characters under a UTF-8 locale, which would
# silently break box alignment depending on the environment. Instead this
# counts raw bytes and subtracts UTF-8 continuation bytes (0x80-0xBF) so the
# result is always the true number of displayed characters, everywhere.
visible_length() {
  local s
  s=$(strip_ansi "$1")
  printf '%s' "$s" | LC_ALL=C od -An -v -tu1 | tr -s ' \n' '\n' | awk '
    NF { if ($1 < 128 || $1 > 191) count++ }
    END { print count + 0 }
  '
}

# Boxed section — single line border (┌─┐ / │ │ / └─┘), color-selectable.
box_top()    { local c="${1:-$BLUE}"; printf "  %s┌%s┐%s\n" "$c" "$(rule '─')" "$RESET"; }
box_bottom() { local c="${1:-$BLUE}"; printf "  %s└%s┘%s\n" "$c" "$(rule '─')" "$RESET"; }
box_sep()    { local c="${1:-$BLUE}"; printf "  %s├%s┤%s\n" "$c" "$(rule '─')" "$RESET"; }

box_line() {
  local content="$1"
  local color="${2:-$BLUE}"
  local vlen pad
  vlen=$(visible_length "$content")
  pad=$(( CONTENT_W - vlen ))
  (( pad < 0 )) && pad=0
  printf "  %s│%s %s%*s %s│%s\n" "$color" "$RESET" "$content" "$pad" "" "$color" "$RESET"
}

# Header — double line border (╔═╗ / ║ ║ / ╚═╝), used once for the banner.
header_top()    { printf "  %s╔%s╗%s\n" "$BLUE" "$(rule '═')" "$RESET"; }
header_bottom() { printf "  %s╚%s╝%s\n" "$BLUE" "$(rule '═')" "$RESET"; }

header_line() {
  local text="$1" style="${2:-}"
  local vlen total_pad left right
  vlen=$(visible_length "$text")
  total_pad=$(( CONTENT_W - vlen ))
  (( total_pad < 0 )) && total_pad=0
  left=$(( total_pad / 2 ))
  right=$(( total_pad - left ))
  printf "  %s║%s %*s%s%s%s%*s %s║%s\n" \
    "$BLUE" "$RESET" "$left" "" "$style" "$text" "$RESET" "$right" "" "$BLUE" "$RESET"
}

# Word-wrap text to a given visible width, one wrapped line per output line.
wrap_text() {
  local text="$1" width="$2"
  local line="" word
  local -a out=()
  for word in $text; do
    if [[ -z "$line" ]]; then
      line="$word"
    elif (( $(visible_length "$line $word") <= width )); then
      line="$line $word"
    else
      out+=("$line")
      line="$word"
    fi
  done
  [[ -n "$line" ]] && out+=("$line")
  printf '%s\n' "${out[@]}"
}

# Aligned "label   value" row for information cards.
kv() {
  printf "%s%-24s%s%s" "$GRAY" "$1" "$RESET" "$2"
}

# Section label printed above a card.
print_section_title() {
  echo
  printf "  %s%s%s\n" "${BOLD}${WHITE}" "$1" "$RESET"
}

# Status badges (bracket-free, professional, no background colors).
badge_ok()   { printf "  %s✓%s  %s\n" "$GREEN"  "$RESET" "$1"; }
badge_err()  { printf "  %s✗%s  %s\n" "$RED"    "$RESET" "$1"; }
badge_warn() { printf "  %s!%s  %s\n" "$YELLOW" "$RESET" "$1"; }
badge_info() { printf "  %si%s  %s\n" "$BLUE"   "$RESET" "$1"; }

# Step header shown before each stage of the workflow.
step() {
  local n="$1" total="$2" title="$3"
  echo
  printf "  %sSTEP %s/%s%s   %s%s%s\n" "$GRAY" "$n" "$total" "$RESET" "${BOLD}${WHITE}" "$title" "$RESET"
  printf "  %s%s%s\n" "$GRAY" "$(rule '─')" "$RESET"
}

# Yes/no confirmation prompt.
confirm() {
  local prompt="$1" answer
  while true; do
    printf "  %s?%s %s %s[y/N]%s " "$YELLOW" "$RESET" "$prompt" "$GRAY" "$RESET"
    read -r answer
    case "$answer" in
      [Yy]|[Yy][Ee][Ss]) return 0 ;;
      [Nn]|[Nn][Oo]|"")  return 1 ;;
      *) printf "  %sPlease answer y or n.%s\n" "$GRAY" "$RESET" ;;
    esac
  done
}

# Full-width error card — used for every failure scenario in the script.
# Message and hint are word-wrapped so text of any length stays inside the box.
print_error_screen() {
  local title="$1" message="$2" hint="${3:-}"
  local wline
  echo
  box_top "$RED"
  box_line "${RED}✗${RESET}  ${BOLD}${title}${RESET}" "$RED"
  box_line "" "$RED"
  while IFS= read -r wline; do
    box_line "$wline" "$RED"
  done < <(wrap_text "$message" "$CONTENT_W")
  if [[ -n "$hint" ]]; then
    box_line "" "$RED"
    while IFS= read -r wline; do
      box_line "${GRAY}${wline}${RESET}" "$RED"
    done < <(wrap_text "$hint" "$CONTENT_W")
  fi
  box_bottom "$RED"
  echo
}

# Runs a command in the background with a smooth animated spinner in front.
# On failure, prints the captured output beneath a red status badge.
run_with_spinner() {
  local msg="$1"; shift
  local logfile
  logfile=$(mktemp)

  ("$@") >"$logfile" 2>&1 &
  local pid=$!
  local frames=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
  local i=0

  if (( IS_TTY )); then
    tput civis 2>/dev/null
    while kill -0 "$pid" 2>/dev/null; do
      printf "\r\033[K  %s%s%s  %s%s%s" "$BLUE" "${frames[i]}" "$RESET" "$GRAY" "$msg" "$RESET"
      i=$(( (i + 1) % ${#frames[@]} ))
      sleep 0.08
    done
    tput cnorm 2>/dev/null
    printf "\r\033[K"
  fi

  wait "$pid"
  local status=$?

  if [[ $status -eq 0 ]]; then
    printf "  %s✓%s  %s\n" "$GREEN" "$RESET" "$msg"
  else
    printf "  %s✗%s  %s\n" "$RED" "$RESET" "$msg"
    echo
    printf "  %sDetails:%s\n" "$GRAY" "$RESET"
    sed 's/^/    /' "$logfile"
    echo
  fi

  rm -f "$logfile"
  return $status
}

# =============================================================================
# STARTUP SCREEN
# =============================================================================

print_main_header() {
  command -v clear &>/dev/null && clear
  echo
  header_top
  header_line ""
  header_line "SSL CERTIFICATE PROVISIONING" "${BOLD}${WHITE}"
  header_line "Let's Encrypt  ·  Manual DNS-01 Challenge" "$GRAY"
  header_line ""
  header_bottom
  echo
  printf "  %sVersion %s%s\n" "$GRAY" "$SCRIPT_VERSION" "$RESET"
}

usage() {
  cat <<EOF
Usage: sudo bash ssl.sh

Obtains a Let's Encrypt SSL certificate using Certbot's manual DNS-01
challenge. Must be run as root. You will be prompted for a domain name
and guided through the DNS TXT record verification process.

Options:
  -h, --help    Show this help message and exit
EOF
}

# =============================================================================
# SYSTEM CHECKS
# =============================================================================

check_root() {
  if [[ $EUID -ne 0 ]]; then
    print_error_screen "Root Privileges Required" \
      "This script must be run as root or with sudo." \
      "Try: sudo bash ssl.sh"
    exit 1
  fi
}

detect_os() {
  if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    OS_ID="${ID,,}"
    OS_LIKE="${ID_LIKE,,}"
  else
    OS_ID="unknown"
    OS_LIKE=""
  fi

  if [[ "$OS_ID" == "ubuntu" || "$OS_ID" == "debian" || "$OS_LIKE" == *debian* ]]; then
    return 0
  fi
  return 1
}

check_internet() {
  if command -v curl &>/dev/null; then
    curl -fsS --max-time 6 -o /dev/null "https://acme-v02.api.letsencrypt.org/directory" && return 0
  fi
  if command -v wget &>/dev/null; then
    wget -q --timeout=6 -O /dev/null "https://acme-v02.api.letsencrypt.org/directory" && return 0
  fi
  ping -c 1 -W 3 1.1.1.1 &>/dev/null && return 0
  return 1
}

ensure_certbot() {
  if command -v certbot &>/dev/null; then
    local ver
    ver=$(certbot --version 2>/dev/null | head -n1)
    badge_ok "Certbot already installed (${ver:-version unknown})"
    return 0
  fi

  badge_warn "Certbot not found — installing now"
  export DEBIAN_FRONTEND=noninteractive

  run_with_spinner "Updating package repositories" apt-get update -y
  local upd=$?
  if [[ $upd -ne 0 ]]; then
    print_error_screen "Package Update Failed" \
      "apt-get update did not complete successfully." \
      "Check your network connection and APT sources, then try again."
    exit 1
  fi

  run_with_spinner "Installing Certbot" apt-get install -y certbot
  local inst=$?
  if [[ $inst -ne 0 ]]; then
    print_error_screen "Certbot Installation Failed" \
      "The package manager could not install certbot." \
      "Try running 'apt-get install -y certbot' manually to see detailed errors."
    exit 1
  fi

  if ! command -v certbot &>/dev/null; then
    print_error_screen "Certbot Not Found" \
      "Installation reported success but the certbot command is unavailable." \
      "Open a new shell session or reinstall certbot manually, then re-run this script."
    exit 1
  fi

  badge_ok "Certbot installed successfully"
}

# =============================================================================
# DOMAIN INPUT & VALIDATION
# =============================================================================

validate_domain() {
  local d="$1"
  local re='^(\*\.)?([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,}$'
  [[ "$d" =~ $re ]]
}

prompt_domain() {
  while true; do
    echo
    printf "  %sEnter the domain name for the certificate%s\n" "$WHITE" "$RESET"
    printf "  %s(e.g. example.com or *.example.com for a wildcard)%s\n" "$GRAY" "$RESET"
    echo
    printf "  %s❯%s " "$BLUE" "$RESET"
    read -r DOMAIN
    DOMAIN="$(printf '%s' "$DOMAIN" | tr -d '[:space:]')"

    if [[ -z "$DOMAIN" ]]; then
      badge_err "Domain cannot be empty — please try again"
      continue
    fi

    if validate_domain "$DOMAIN"; then
      badge_ok "Domain accepted: ${DOMAIN}"
      break
    else
      badge_err "Invalid domain format: ${DOMAIN}"
    fi
  done
}

# =============================================================================
# CERTIFICATE HELPERS
# =============================================================================

get_expiry() {
  local cert="$1" raw
  if ! command -v openssl &>/dev/null || [[ ! -f "$cert" ]]; then
    echo "Unavailable"
    return
  fi
  raw=$(openssl x509 -enddate -noout -in "$cert" 2>/dev/null | sed 's/^notAfter=//')
  if [[ -z "$raw" ]]; then
    echo "Unavailable"
    return
  fi
  if date -d "$raw" '+%d %B %Y, %H:%M UTC' &>/dev/null; then
    date -d "$raw" '+%d %B %Y, %H:%M UTC'
  else
    echo "$raw"
  fi
}

check_existing_certificate() {
  local domain="$1"
  local live="/etc/letsencrypt/live/$domain"

  if [[ -d "$live" ]]; then
    local expiry="Unavailable"
    [[ -f "$live/fullchain.pem" ]] && expiry=$(get_expiry "$live/fullchain.pem")

    echo
    print_section_title "Existing Certificate Found"
    box_top "$YELLOW"
    box_line "A certificate for ${WHITE}${domain}${RESET} already exists." "$YELLOW"
    box_line "" "$YELLOW"
    box_line "$(kv "Current Expiry" "$expiry")" "$YELLOW"
    box_line "$(kv "Location" "$live")" "$YELLOW"
    box_bottom "$YELLOW"
    echo

    if ! confirm "Continue and overwrite this certificate?"; then
      print_error_screen "Cancelled by User" \
        "No changes were made to the existing certificate." \
        "Re-run this script when you are ready to proceed."
      exit 130
    fi
  fi
}

# =============================================================================
# DNS-01 CHALLENGE
# =============================================================================

show_dns_instructions() {
  echo
  print_section_title "DNS-01 Challenge Instructions"
  box_top
  box_line "Certbot will now request a domain ownership challenge."
  box_line ""
  box_line "${WHITE}1.${RESET} Certbot will display a TXT record name and value below."
  box_line "${WHITE}2.${RESET} Open your DNS provider's control panel."
  box_line "${WHITE}3.${RESET} Create the requested TXT record exactly as shown."
  box_line "${WHITE}4.${RESET} Wait a few minutes for DNS propagation to complete."
  box_line "${WHITE}5.${RESET} Return to this terminal and press Enter to continue."
  box_line ""
  box_line "${GRAY}Tip — verify propagation before continuing:${RESET}"
  box_line "${GRAY}  dig +short TXT _acme-challenge.<yourdomain>${RESET}"
  box_bottom
  echo
  printf "  %sPress Enter when you are ready to begin the challenge...%s" "$GRAY" "$RESET"
  read -r _
}

run_certbot() {
  local domain="$1"
  echo
  badge_info "Launching Certbot — follow the on-screen prompts below"
  echo
  certbot certonly \
    --manual \
    --preferred-challenges dns \
    --register-unsafely-without-email \
    --agree-tos \
    -d "$domain"
  return $?
}

show_certbot_failure() {
  local status="${1:-unknown}"
  print_error_screen "Certificate Issuance Failed" \
    "Certbot exited with status ${status} before a certificate could be issued." \
    "Common causes: the TXT record has not propagated yet, an incorrect record value, rate limiting, or the process was cancelled. Verify the DNS record and try again."
}

# =============================================================================
# SUCCESS SCREEN
# =============================================================================

show_success() {
  local domain="$1"
  local live="/etc/letsencrypt/live/$domain"
  local fullchain="$live/fullchain.pem"
  local privkey="$live/privkey.pem"
  local chain="$live/chain.pem"
  local expiry
  expiry=$(get_expiry "$fullchain")

  echo
  box_top "$GREEN"
  box_line "${GREEN}✓${RESET}  ${BOLD}Certificate issued successfully${RESET}" "$GREEN"
  box_bottom "$GREEN"

  print_section_title "Certificate Details"
  box_top
  box_line "$(kv "Domain" "$domain")"
  box_line "$(kv "Expires" "$expiry")"
  box_sep
  box_line "${GRAY}Certificate (fullchain)${RESET}"
  box_line "  ${fullchain}"
  box_line ""
  box_line "${GRAY}Private Key${RESET}"
  box_line "  ${privkey}"
  box_line ""
  box_line "${GRAY}Chain${RESET}"
  box_line "  ${chain}"
  box_sep
  box_line "$(kv "Certbot Root" "/etc/letsencrypt/")"
  box_line "$(kv "Live Directory" "/etc/letsencrypt/live/")"
  box_line "$(kv "Archive Directory" "/etc/letsencrypt/archive/")"
  box_line "$(kv "Renewal Directory" "/etc/letsencrypt/renewal/")"
  box_bottom

  print_section_title "Renewal"
  box_top
  box_line "Run the following command to renew this certificate later:"
  box_line ""
  box_line "  ${WHITE}sudo certbot renew${RESET}"
  box_line ""
  box_line "${GRAY}This certificate uses the manual DNS-01 plugin, so renewal will${RESET}"
  box_line "${GRAY}prompt you to update the DNS TXT record again unless you set up${RESET}"
  box_line "${GRAY}a --manual-auth-hook automation script.${RESET}"
  box_bottom
  echo
  printf "  %sDone. Your certificate is ready to use.%s\n\n" "$GRAY" "$RESET"
}

# =============================================================================
# SIGNAL HANDLING
# =============================================================================

on_cancel() {
  (( IS_TTY )) && tput cnorm 2>/dev/null
  echo
  print_error_screen "Operation Cancelled" \
    "The script was interrupted (Ctrl+C)." \
    "No certificate changes were made beyond what is noted above."
  exit 130
}
trap on_cancel INT
trap '(( IS_TTY )) && tput cnorm 2>/dev/null; true' EXIT

# =============================================================================
# MAIN
# =============================================================================

main() {
  case "${1:-}" in
    -h|--help) usage; exit 0 ;;
  esac

  print_main_header

  step 1 "$STEP_TOTAL" "Verifying root privileges"
  check_root
  badge_ok "Running with root privileges"

  step 2 "$STEP_TOTAL" "Detecting operating system"
  if detect_os; then
    badge_ok "Detected supported OS: ${PRETTY_NAME:-$OS_ID}"
  else
    print_error_screen "Unsupported Operating System" \
      "This script supports Ubuntu and Debian-based systems only." \
      "Detected: ${PRETTY_NAME:-unknown}"
    exit 1
  fi

  step 3 "$STEP_TOTAL" "Checking internet connectivity"
  run_with_spinner "Checking internet connectivity" check_internet
  local net_status=$?
  if [[ $net_status -ne 0 ]]; then
    print_error_screen "No Internet Connection" \
      "Unable to reach Let's Encrypt servers." \
      "Check your network connection, DNS, and firewall settings, then try again."
    exit 1
  fi

  step 4 "$STEP_TOTAL" "Checking Certbot installation"
  ensure_certbot

  step 5 "$STEP_TOTAL" "Domain configuration"
  prompt_domain

  step 6 "$STEP_TOTAL" "Checking for existing certificates"
  check_existing_certificate "$DOMAIN"
  badge_ok "Certificate check complete"

  step 7 "$STEP_TOTAL" "DNS-01 challenge"
  show_dns_instructions
  run_certbot "$DOMAIN"
  local certbot_status=$?

  if [[ $certbot_status -eq 0 && -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]]; then
    show_success "$DOMAIN"
  else
    show_certbot_failure "$certbot_status"
    exit 1
  fi
}

main "$@"
