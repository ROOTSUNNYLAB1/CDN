#!/usr/bin/env bash
# ROOTSUNNYLAB • Pterodactyl Blueprint Installer
# Comprehensive installer / updater / repair / backup / uninstall + Pterodactyl restore.
# Based on the Blueprint install, update and removal material supplied by the user.
set -Eeuo pipefail
IFS=$'\n\t'

VERSION="3.1.0"
PTERODACTYL_DIRECTORY="${PTERODACTYL_DIRECTORY:-/var/www/pterodactyl}"
BLUEPRINT_RELEASE_URL="https://github.com/BlueprintFramework/framework/releases/latest/download/release.zip"
PTERODACTYL_RELEASE_URL="https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz"
NODE_MAJOR=22
BACKUP_ROOT="/var/backups/rootsunnylab-blueprint"
LOG_FILE="/var/log/rootsunnylab-blueprint.log"

if [[ -t 1 ]]; then
  BOLD=$'\033[1m'; DIM=$'\033[2m'; RESET=$'\033[0m'; GREEN=$'\033[92m'; YELLOW=$'\033[93m'; RED=$'\033[91m'; CYAN=$'\033[96m'; WHITE=$'\033[97m'
else BOLD= DIM= RESET= GREEN= YELLOW= RED= CYAN= WHITE=; fi

exists(){ command -v "$1" >/dev/null 2>&1; }
root(){ if (( EUID == 0 )); then "$@"; else sudo "$@"; fi; }
log(){ printf '[%s] %s\n' "$(date '+%F %T')" "$*" >> "$LOG_FILE" 2>/dev/null || true; }
info(){ printf '  %s•%s %s\n' "$CYAN" "$RESET" "$*"; }
ok(){ printf '%s✓%s %s\n' "$GREEN" "$RESET" "$*"; log "OK: $*"; }
warn(){ printf '%s!%s %s\n' "$YELLOW" "$RESET" "$*"; log "WARN: $*"; }
die(){ printf '%s✕ ERROR:%s %s\n' "$RED" "$RESET" "$*" >&2; log "ERROR: $*"; exit 1; }
ask(){ local a < /dev/tty; read -r -p "$1 [y/N] " a < /dev/tty; [[ $a =~ ^[Yy]$ ]]; }
run(){ local label=$1; shift; printf '  %s…%s %s\n' "$DIM" "$RESET" "$label"; log "RUN: $label"; "$@" >>"$LOG_FILE" 2>&1 || die "$label failed. See $LOG_FILE"; ok "$label"; }

root mkdir -p "$(dirname "$LOG_FILE")" "$BACKUP_ROOT" 2>/dev/null || true
touch "$LOG_FILE" 2>/dev/null || true

banner(){ clear 2>/dev/null || true; cat <<'EOF'

██████╗  ██████╗  ██████╗ ████████╗███████╗██╗   ██╗███╗   ██╗██╗  ██╗██╗   ██╗
██╔══██╗██╔═══██╗██╔═══██╗╚══██╔══╝██╔════╝██║   ██║████╗  ██║██║  ██║╚██╗ ██╔╝
██████╔╝██║   ██║██║   ██║   ██║   ███████╗██║   ██║██╔██╗ ██║███████║ ╚████╔╝
██╔══██╗██║   ██║██║   ██║   ██║   ╚════██║██║   ██║██║╚██╗██║██╔══██║  ╚██╔╝
██║  ██║╚██████╔╝╚██████╔╝   ██║   ███████║╚██████╔╝██║ ╚████║██║  ██║   ██║
╚═╝  ╚═╝ ╚═════╝  ╚═════╝    ╚═╝   ╚══════╝╚═════╝ ╚═╝  ╚═══╝╚═╝  ╚═╝   ╚═╝

                 P T E R O D A C T Y L   B L U E P R I N T
                  ROOTSUNNYLAB • BLUEPRINT INSTALLER
EOF
printf '\n%sVersion %s • No-neon • Safe workflow • ROOTSUNNYLAB%s\n\n' "$DIM" "$VERSION" "$RESET"; }

preflight(){
  [[ $(uname -s) == Linux ]] || die "Linux is required."
  [[ -r /etc/os-release ]] || die "/etc/os-release not found."; . /etc/os-release
  OS_ID=${ID:-unknown}; OS_LIKE=${ID_LIKE:-}
  if exists apt-get; then PKG=apt; elif exists dnf; then PKG=dnf; elif exists yum; then PKG=yum; elif exists pacman; then PKG=pacman; elif exists zypper; then PKG=zypper; elif exists apk; then PKG=apk; else die "Supported package manager not found."; fi
  info "OS: ${PRETTY_NAME:-$OS_ID}"; info "Architecture: $(uname -m)"; info "Pterodactyl: $PTERODACTYL_DIRECTORY"; info "Package manager: $PKG"
  [[ -d "$PTERODACTYL_DIRECTORY" ]] && exists df && info "Free disk: $(df -h "$PTERODACTYL_DIRECTORY" | awk 'NR==2{print $4}')"
}

packages(){
  case $PKG in
    apt) run "Update APT" root apt-get update -y; run "Install base dependencies" root apt-get install -y ca-certificates curl git gnupg unzip wget zip bash tar;;
    dnf) run "Install base dependencies" root dnf install -y ca-certificates curl git gnupg2 unzip wget zip bash tar;;
    yum) run "Install base dependencies" root yum install -y ca-certificates curl git gnupg2 unzip wget zip bash tar;;
    pacman) run "Install base dependencies" root pacman -Sy --noconfirm ca-certificates curl git gnupg unzip wget zip bash tar;;
    zypper) run "Refresh repositories" root zypper --non-interactive refresh; run "Install base dependencies" root zypper --non-interactive install ca-certificates curl gpg2 unzip wget zip bash tar;;
    apk) run "Install base dependencies" root apk add --no-cache ca-certificates curl git gnupg unzip wget zip bash tar;;
  esac
}

node_setup(){
  if exists node && [[ $(node -v) == v22.* ]]; then ok "Node.js $(node -v)"; else
    case $PKG in
      apt)
        root mkdir -p /etc/apt/keyrings
        local key; key=$(mktemp); curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key -o "$key" || die "NodeSource key download failed"; root gpg --dearmor < "$key" > /tmp/nodesource.gpg; root mv /tmp/nodesource.gpg /etc/apt/keyrings/nodesource.gpg; rm -f "$key"
        root bash -c 'echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" > /etc/apt/sources.list.d/nodesource.list'; run "Update NodeSource repository" root apt-get update -y; run "Install Node.js 22" root apt-get install -y nodejs;;
      dnf) curl -fsSL https://rpm.nodesource.com/setup_22.x | root bash -; run "Install Node.js 22" root dnf install -y nodejs;;
      yum) curl -fsSL https://rpm.nodesource.com/setup_22.x | root bash -; run "Install Node.js 22" root yum install -y nodejs;;
      pacman) run "Install Node.js and npm" root pacman -S --noconfirm nodejs npm;;
      zypper) run "Install Node.js and npm" root zypper --non-interactive install nodejs npm;;
      apk) run "Install Node.js and npm" root apk add --no-cache nodejs npm;;
    esac
  fi
  exists node || die "Node.js unavailable."; exists npm || die "npm unavailable."; exists yarn || run "Install Yarn" root npm i -g yarn
}

configure(){
  local rc="$PTERODACTYL_DIRECTORY/.blueprintrc" user=www-data owner=www-data:www-data
  for u in www-data nginx apache caddy nobody; do if id "$u" >/dev/null 2>&1; then user=$u; owner="$u:$u"; break; fi; done
  root tee "$rc" >/dev/null <<EOF
WEBUSER="$user";
OWNERSHIP="$owner";
USERSHELL="/bin/bash";
EOF
  ok "Configured .blueprintrc ($user / $owner)"
}

install(){
  preflight; [[ -d "$PTERODACTYL_DIRECTORY" ]] || root mkdir -p "$PTERODACTYL_DIRECTORY"
  packages; node_setup
  local d; d=$(mktemp -d); trap 'rm -rf "$d"' RETURN
  run "Download latest Blueprint release" curl -fL --retry 3 "$BLUEPRINT_RELEASE_URL" -o "$d/release.zip"
  [[ -s "$d/release.zip" ]] || die "Blueprint archive is empty."
  run "Extract Blueprint into Pterodactyl" root unzip -o "$d/release.zip" -d "$PTERODACTYL_DIRECTORY"
  configure
  cd "$PTERODACTYL_DIRECTORY"
  run "Install Node dependencies" yarn install
  [[ ! -f blueprint.sh ]] || run "Set blueprint.sh executable" root chmod +x blueprint.sh
  ok "Blueprint installation complete"
}

update(){
  preflight; cd "$PTERODACTYL_DIRECTORY"; exists blueprint || [[ -x blueprint.sh ]] || die "Blueprint is not installed."
  cat <<'EOF'

ROOTSUNNYLAB • UPDATE BLUEPRINT
  1  Latest stable release        (blueprint -upgrade)
  2  Latest GitHub commit         (development / unsupported)
  3  Latest commit of a fork      (organization/repository)
  0  Back
EOF
  read -r -p 'Select [0-3]: ' c < /dev/tty < /dev/tty
  case $c in
    1) run "Update Blueprint stable release" blueprint -upgrade;;
    2) warn "Development commits may break and are unsupported."; ask "Continue?" && run "Update Blueprint development commit" blueprint -upgrade remote;;
    3) read -r -p 'GitHub repository (organization/repository): ' r < /dev/tty; [[ $r =~ ^[^/]+/[^/]+$ ]] || die "Invalid repository."; run "Update Blueprint custom fork" blueprint -upgrade remote "$r";;
    0) return;; *) warn "Invalid choice.";;
  esac
}

backup(){
  [[ -d "$PTERODACTYL_DIRECTORY" ]] || die "Pterodactyl directory not found."
  local stamp dir; stamp=$(date +%Y%m%d-%H%M%S); dir="$BACKUP_ROOT/$stamp"; root mkdir -p "$dir"
  run "Full Pterodactyl web-directory backup" root tar -czf "$dir/pterodactyl-webserver.tar.gz" -C "$(dirname "$PTERODACTYL_DIRECTORY")" "$(basename "$PTERODACTYL_DIRECTORY")"
  [[ -f "$PTERODACTYL_DIRECTORY/.env" ]] && run "Separate .env / APP_KEY backup" root cp -a "$PTERODACTYL_DIRECTORY/.env" "$dir/.env"
  [[ -f "$PTERODACTYL_DIRECTORY/.blueprintrc" ]] && run "Separate Blueprint config backup" root cp -a "$PTERODACTYL_DIRECTORY/.blueprintrc" "$dir/.blueprintrc"
  printf '%sBackup: %s%s\n' "$GREEN" "$dir" "$RESET"
}

update_panel_blueprint(){
  preflight
  cd "$PTERODACTYL_DIRECTORY"
  [[ -f .env ]] || die ".env is missing; refusing to update without preserving APP_KEY."
  exists php || die "PHP is required."
  exists composer || die "Composer is required."
  exists curl || die "curl is required."
  if ! exists blueprint; then [[ -x blueprint.sh ]] || die "Blueprint is not installed."; fi

  warn "This updates BOTH Pterodactyl and Blueprint. Your .env / APP_KEY will be preserved."
  warn "A complete web-directory backup is strongly recommended before continuing."
  ask "Create a backup before updating?" && backup
  ask "Continue with Pterodactyl + Blueprint update?" || return

  local work archive env
  work=$(mktemp -d)
  archive="$work/panel.tar.gz"
  env="$work/.env"
  cp -a "$PTERODACTYL_DIRECTORY/.env" "$env"
  trap 'rm -rf "$work"' RETURN

  run "Enter Pterodactyl maintenance mode" php artisan down
  run "Download latest Pterodactyl release" curl -fL --retry 3 "$PTERODACTYL_RELEASE_URL" -o "$archive"
  [[ -s "$archive" ]] || die "Pterodactyl archive is empty."
  run "Extract latest Pterodactyl release" tar -xzvf "$archive" -C "$PTERODACTYL_DIRECTORY"
  run "Restore original .env / APP_KEY" cp -a "$env" "$PTERODACTYL_DIRECTORY/.env"
  run "Set storage and cache permissions" bash -c "cd '$PTERODACTYL_DIRECTORY' && chmod -R 755 storage/* bootstrap/cache"
  run "Install Pterodactyl dependencies" bash -c "cd '$PTERODACTYL_DIRECTORY' && COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader"
  run "Update Pterodactyl database schema" php artisan migrate --seed --force
  run "Update Blueprint and restore Blueprint changes" blueprint -upgrade
  run "Exit Pterodactyl maintenance mode" php artisan up
  ok "Pterodactyl + Blueprint update completed successfully"
}

restore_panel(){
  local work env archive owner=www-data:www-data; work=$(mktemp -d); env="$work/.env"; archive="$work/panel.tar.gz"
  [[ -f "$PTERODACTYL_DIRECTORY/.env" ]] || die ".env is missing; APP_KEY cannot be safely preserved."
  run "Stage .env / APP_KEY" cp -a "$PTERODACTYL_DIRECTORY/.env" "$env"
  cd "$PTERODACTYL_DIRECTORY"; run "Enter Pterodactyl maintenance mode" php artisan down
  run "Remove old Pterodactyl web files" bash -c "find '$PTERODACTYL_DIRECTORY' -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +"
  run "Download latest Pterodactyl panel" curl -fL --retry 3 "$PTERODACTYL_RELEASE_URL" -o "$archive"
  [[ -s "$archive" ]] || die "Pterodactyl archive is empty."
  run "Extract latest Pterodactyl panel" tar -xzvf "$archive" -C "$PTERODACTYL_DIRECTORY"
  run "Restore original .env / APP_KEY" cp -a "$env" "$PTERODACTYL_DIRECTORY/.env"
  run "Set storage and cache permissions" bash -c "cd '$PTERODACTYL_DIRECTORY' && chmod -R 755 storage/* bootstrap/cache"
  exists composer || die "Composer is required for Pterodactyl restoration."
  run "Install Pterodactyl dependencies" bash -c "cd '$PTERODACTYL_DIRECTORY' && COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader"
  run "Clear compiled view cache" php artisan view:clear
  run "Clear config cache" php artisan config:clear
  run "Run database migrations and seed" php artisan migrate --seed --force
  if [[ "$OS_ID" =~ ^(centos|rhel|rocky|almalinux)$ ]] && id nginx >/dev/null 2>&1; then owner=nginx:nginx; elif [[ "$OS_ID" =~ ^(centos|rhel|rocky|almalinux)$ ]] && id apache >/dev/null 2>&1; then owner=apache:apache; elif id www-data >/dev/null 2>&1; then owner=www-data:www-data; elif id nginx >/dev/null 2>&1; then owner=nginx:nginx; elif id caddy >/dev/null 2>&1; then owner=caddy:caddy; fi
  run "Set Pterodactyl ownership ($owner)" root chown -R "$owner" "$PTERODACTYL_DIRECTORY/"
  run "Restart queue workers" php artisan queue:restart
  run "Exit maintenance mode" php artisan up
  rm -rf "$work"
}

uninstall(){
  preflight; [[ -f "$PTERODACTYL_DIRECTORY/.env" ]] || die "No .env found. Refusing to risk APP_KEY/panel data."
  warn "Blueprint removal requires replacing the Pterodactyl web files. A full backup and separate .env backup will be created first."
  warn "Database is external to the web directory; keep a database backup too."
  ask "Create backup and continue?" || return
  backup
  printf '\n%sType UNINSTALL to continue:%s ' "$RED" "$RESET"; read -r phrase < /dev/tty; [[ $phrase == UNINSTALL ]] || { warn "Cancelled."; return; }
  restore_panel
  ok "Blueprint removed and Pterodactyl restored in $PTERODACTYL_DIRECTORY"
}

reinstall(){ preflight; warn "Blueprint reinstall does not intentionally delete .env or the panel database."; ask "Continue?" || return; install; }
repair(){ preflight; packages; node_setup; configure; cd "$PTERODACTYL_DIRECTORY"; run "Install/repair Yarn dependencies" yarn install; [[ ! -f blueprint.sh ]] || run "Fix blueprint.sh permission" root chmod +x blueprint.sh; ok "Repair complete"; }
doctor(){ preflight; printf '\nPHP: '; exists php && php -v | head -1 || echo missing; printf 'Composer: '; exists composer && composer --version | head -1 || echo missing; printf 'Node: '; exists node && node -v || echo missing; printf 'npm: '; exists npm && npm -v || echo missing; printf 'Yarn: '; exists yarn && yarn -v || echo missing; printf 'Blueprint: '; exists blueprint && echo available || echo missing; [[ -f "$PTERODACTYL_DIRECTORY/.env" ]] && ok '.env present' || warn '.env missing'; [[ -f "$PTERODACTYL_DIRECTORY/.blueprintrc" ]] && ok '.blueprintrc present' || warn '.blueprintrc missing'; }
config(){ preflight; printf '\nPterodactyl directory : %s\nBlueprint release URL : %s\nBackup directory      : %s\nLog file              : %s\n' "$PTERODACTYL_DIRECTORY" "$BLUEPRINT_RELEASE_URL" "$BACKUP_ROOT" "$LOG_FILE"; [[ -f "$PTERODACTYL_DIRECTORY/.blueprintrc" ]] && { echo; cat "$PTERODACTYL_DIRECTORY/.blueprintrc"; }; }
dryrun(){ preflight; cat <<EOF

DRY RUN — no changes will be made.
Install: dependencies → Node.js 22 → Blueprint release → .blueprintrc → yarn install.
Update Blueprint: blueprint -upgrade / remote / custom fork only.
Update Pterodactyl + Blueprint: maintenance mode → latest panel → permissions → composer → database → blueprint -upgrade → production.
Uninstall: full web backup → separate .env → maintenance mode → replace panel files → restore .env → composer → caches → migrations → ownership → queue restart → panel up.
Backup: $BACKUP_ROOT
EOF
}

menu(){ while true; do banner; cat <<'EOF'
╭──────────────────────────────────────────────────────────╮
│ ROOTSUNNYLAB • BLUEPRINT INSTALLER                       │
├──────────────────────────────────────────────────────────┤
│                                                          │
│  1  Install Blueprint                                    │
│  2  Update Blueprint                                     │
│  3  Update Pterodactyl + Blueprint                       │
│  4  Reinstall Blueprint                                  │
│  5  Repair Installation                                  │
│  6  Check System / Doctor                                │
│  7  Show Configuration                                   │
│  8  Uninstall Blueprint + Restore Pterodactyl            │
│  9  Full Backup                                          │
│ 10  Dry Run / Preview                                    │
│ 11  View Installer Log                                   │
│  0  Exit                                                 │
│                                                          │
╰──────────────────────────────────────────────────────────╯
EOF
read -r -p 'Select an option [0-11]: ' c < /dev/tty; case $c in 1) install;; 2) update;; 3) update_panel_blueprint;; 4) reinstall;; 5) repair;; 6) doctor;; 7) config;; 8) uninstall;; 9) preflight; backup;; 10) dryrun;; 11) tail -n 100 "$LOG_FILE" 2>/dev/null || true;; 0) exit 0;; *) warn 'Invalid selection.';; esac; echo; read -r -p 'Press Enter to continue...' _ < /dev/tty; done; }

case ${1:-} in
  --install) install;; --update) update;; --update-panel-blueprint) update_panel_blueprint;; --reinstall) reinstall;; --repair) repair;; --doctor) doctor;; --config) config;; --uninstall) uninstall;; --backup) preflight; backup;; --dry-run) dryrun;; --version) echo "$VERSION";; --help|-h) echo "ROOTSUNNYLAB Blueprint Installer $VERSION"; echo "Usage: $0 [--install|--update|--update-panel-blueprint|--reinstall|--repair|--doctor|--config|--uninstall|--backup|--dry-run]";; *) menu;; esac
