#!/usr/bin/env bash
# ROOTSUNNYLAB • Pterodactyl Blueprint Installer
# Synced from ROOTSUNNYLAB1/LAB blueprint.sh v3.0.0
# Full installer / Blueprint updater / repair / doctor / backup / safe Pterodactyl restore.
set -Eeuo pipefail
IFS=$'\n\t'
VERSION="3.0.0"
PTERODACTYL_DIRECTORY="${PTERODACTYL_DIRECTORY:-/var/www/pterodactyl}"
BLUEPRINT_RELEASE_URL="https://github.com/BlueprintFramework/framework/releases/latest/download/release.zip"
PTERODACTYL_RELEASE_URL="https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz"
BACKUP_ROOT="/var/backups/rootsunnylab-blueprint"
LOG_FILE="/var/log/rootsunnylab-blueprint.log"
if [[ -t 1 ]]; then GREEN=$'\033[92m';YELLOW=$'\033[93m';RED=$'\033[91m';CYAN=$'\033[96m';DIM=$'\033[2m';RESET=$'\033[0m'; else GREEN= YELLOW= RED= CYAN= DIM= RESET=; fi
exists(){ command -v "$1" >/dev/null 2>&1; }
root(){ (( EUID == 0 )) && "$@" || sudo "$@"; }
log(){ printf '[%s] %s\n' "$(date '+%F %T')" "$*" >>"$LOG_FILE" 2>/dev/null || true; }
ok(){ printf '%s✓%s %s\n' "$GREEN" "$RESET" "$*";log "OK: $*"; }
warn(){ printf '%s!%s %s\n' "$YELLOW" "$RESET" "$*";log "WARN: $*"; }
die(){ printf '%s✕ ERROR:%s %s\n' "$RED" "$RESET" "$*" >&2;log "ERROR: $*";exit 1; }
ask(){ local a;read -r -p "$1 [y/N] " a;[[ $a =~ ^[Yy]$ ]]; }
run(){ local label=$1;shift;printf '  %s…%s %s\n' "$DIM" "$RESET" "$label";log "RUN: $label";"$@" >>"$LOG_FILE" 2>&1 || die "$label failed. See $LOG_FILE";ok "$label"; }
root mkdir -p "$(dirname "$LOG_FILE")" "$BACKUP_ROOT" 2>/dev/null || true;touch "$LOG_FILE" 2>/dev/null || true
banner(){ clear 2>/dev/null || true;cat <<'EOF'
╭──────────────────────────────────────────────────────────╮
│ ROOTSUNNYLAB • BLUEPRINT INSTALLER                       │
│ PTERODACTYL MODDING PLATFORM                             │
├──────────────────────────────────────────────────────────┤
│                    ROOTSUNNYLAB                          │
╰──────────────────────────────────────────────────────────╯
EOF
printf '%sVersion %s • No-neon • Safe workflow%s\n\n' "$DIM" "$VERSION" "$RESET"; }
preflight(){ [[ $(uname -s) == Linux ]]||die 'Linux is required.';[[ -r /etc/os-release ]]||die '/etc/os-release not found.';. /etc/os-release;OS_ID=${ID:-unknown};if exists apt-get;then PKG=apt;elif exists dnf;then PKG=dnf;elif exists yum;then PKG=yum;elif exists pacman;then PKG=pacman;elif exists zypper;then PKG=zypper;elif exists apk;then PKG=apk;else die 'Supported package manager not found.';fi;printf 'OS: %s\nArchitecture: %s\nPterodactyl: %s\nPackage manager: %s\n' "${PRETTY_NAME:-$OS_ID}" "$(uname -m)" "$PTERODACTYL_DIRECTORY" "$PKG"; }
packages(){ case $PKG in apt) run 'Update APT' root apt-get update -y;run 'Install dependencies' root apt-get install -y ca-certificates curl git gnupg unzip wget zip bash tar;;dnf) run 'Install dependencies' root dnf install -y ca-certificates curl git gnupg2 unzip wget zip bash tar;;yum) run 'Install dependencies' root yum install -y ca-certificates curl git gnupg2 unzip wget zip bash tar;;pacman) run 'Install dependencies' root pacman -Sy --noconfirm ca-certificates curl git gnupg unzip wget zip bash tar;;zypper) run 'Refresh repositories' root zypper --non-interactive refresh;run 'Install dependencies' root zypper --non-interactive install ca-certificates curl gpg2 unzip wget zip bash tar;;apk) run 'Install dependencies' root apk add --no-cache ca-certificates curl git gnupg unzip wget zip bash tar;;esac; }
node_setup(){ if ! exists node || [[ $(node -v) != v22.* ]];then case $PKG in apt) root mkdir -p /etc/apt/keyrings;curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key|root gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg;root bash -c 'echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" >/etc/apt/sources.list.d/nodesource.list';run 'Update NodeSource repository' root apt-get update -y;run 'Install Node.js 22' root apt-get install -y nodejs;;dnf) curl -fsSL https://rpm.nodesource.com/setup_22.x|root bash -;run 'Install Node.js 22' root dnf install -y nodejs;;yum) curl -fsSL https://rpm.nodesource.com/setup_22.x|root bash -;run 'Install Node.js 22' root yum install -y nodejs;;pacman) run 'Install Node.js and npm' root pacman -S --noconfirm nodejs npm;;zypper) run 'Install Node.js and npm' root zypper --non-interactive install nodejs npm;;apk) run 'Install Node.js and npm' root apk add --no-cache nodejs npm;;esac;fi;exists node||die 'Node.js unavailable.';exists npm||die 'npm unavailable.';exists yarn||run 'Install Yarn' root npm i -g yarn; }
configure(){ local rc="$PTERODACTYL_DIRECTORY/.blueprintrc" user=www-data owner=www-data:www-data;for u in www-data nginx apache caddy nobody;do if id "$u" >/dev/null 2>&1;then user=$u;owner="$u:$u";break;fi;done;root tee "$rc" >/dev/null <<EOF
WEBUSER="$user";
OWNERSHIP="$owner";
USERSHELL="/bin/bash";
EOF
ok "Configured .blueprintrc ($user / $owner)"; }
install(){ preflight;[[ -d "$PTERODACTYL_DIRECTORY" ]]||root mkdir -p "$PTERODACTYL_DIRECTORY";packages;node_setup;local d;d=$(mktemp -d);run 'Download latest Blueprint release' curl -fL --retry 3 "$BLUEPRINT_RELEASE_URL" -o "$d/release.zip";[[ -s "$d/release.zip" ]]||die 'Blueprint archive is empty.';run 'Extract Blueprint into Pterodactyl' root unzip -o "$d/release.zip" -d "$PTERODACTYL_DIRECTORY";configure;cd "$PTERODACTYL_DIRECTORY";run 'Install Node dependencies' yarn install;[[ ! -f blueprint.sh ]]||run 'Set blueprint.sh executable' root chmod +x blueprint.sh;rm -rf "$d";ok 'Blueprint installation complete'; }
update(){ preflight;cd "$PTERODACTYL_DIRECTORY";exists blueprint||[[ -x blueprint.sh ]]||die 'Blueprint is not installed.';cat <<'EOF'
╭──────────────────────────────────────────╮
│ ROOTSUNNYLAB • UPDATE BLUEPRINT          │
├──────────────────────────────────────────┤
│  1  Latest stable release                │
│  2  Latest GitHub commit                 │
│  3  Latest commit of a fork              │
│  0  Back                                 │
╰──────────────────────────────────────────╯
EOF
read -r -p 'Select [0-3]: ' c;case $c in 1)run 'Update Blueprint stable release' blueprint -upgrade;;2)warn 'Development commits may break and are unsupported.';ask 'Continue?'&&run 'Update Blueprint development commit' blueprint -upgrade remote;;3)read -r -p 'GitHub repository (organization/repository): ' r;[[ $r =~ ^[^/]+/[^/]+$ ]]||die 'Invalid repository.';run 'Update Blueprint custom fork' blueprint -upgrade remote "$r";;0)return;;*)warn 'Invalid choice.';;esac; }
backup(){ [[ -d "$PTERODACTYL_DIRECTORY" ]]||die 'Pterodactyl directory not found.';local stamp dir;stamp=$(date +%Y%m%d-%H%M%S);dir="$BACKUP_ROOT/$stamp";root mkdir -p "$dir";run 'Full Pterodactyl web-directory backup' root tar -czf "$dir/pterodactyl-webserver.tar.gz" -C "$(dirname "$PTERODACTYL_DIRECTORY")" "$(basename "$PTERODACTYL_DIRECTORY")";[[ -f "$PTERODACTYL_DIRECTORY/.env" ]]&&run 'Separate .env / APP_KEY backup' root cp -a "$PTERODACTYL_DIRECTORY/.env" "$dir/.env";[[ -f "$PTERODACTYL_DIRECTORY/.blueprintrc" ]]&&run 'Separate Blueprint config backup' root cp -a "$PTERODACTYL_DIRECTORY/.blueprintrc" "$dir/.blueprintrc";printf '%sBackup: %s%s\n' "$GREEN" "$dir" "$RESET"; }
restore_panel(){ local work env archive owner=www-data:www-data;work=$(mktemp -d);env="$work/.env";archive="$work/panel.tar.gz";[[ -f "$PTERODACTYL_DIRECTORY/.env" ]]||die '.env is missing; APP_KEY cannot be safely preserved.';run 'Stage .env / APP_KEY' cp -a "$PTERODACTYL_DIRECTORY/.env" "$env";cd "$PTERODACTYL_DIRECTORY";run 'Enter Pterodactyl maintenance mode' php artisan down;run 'Remove old Pterodactyl web files' bash -c "find '$PTERODACTYL_DIRECTORY' -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +";run 'Download latest Pterodactyl panel' curl -fL --retry 3 "$PTERODACTYL_RELEASE_URL" -o "$archive";[[ -s "$archive" ]]||die 'Pterodactyl archive is empty.';run 'Extract latest Pterodactyl panel' tar -xzvf "$archive" -C "$PTERODACTYL_DIRECTORY";run 'Restore original .env / APP_KEY' cp -a "$env" "$PTERODACTYL_DIRECTORY/.env";run 'Set storage and cache permissions' bash -c "cd '$PTERODACTYL_DIRECTORY'&&chmod -R 755 storage/* bootstrap/cache";exists composer||die 'Composer is required for Pterodactyl restoration.';run 'Install Pterodactyl dependencies' bash -c "cd '$PTERODACTYL_DIRECTORY'&&COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader";run 'Clear compiled view cache' php artisan view:clear;run 'Clear config cache' php artisan config:clear;run 'Run database migrations and seed' php artisan migrate --seed --force;if id www-data >/dev/null 2>&1;then owner=www-data:www-data;elif id nginx >/dev/null 2>&1;then owner=nginx:nginx;elif id apache >/dev/null 2>&1;then owner=apache:apache;elif id caddy >/dev/null 2>&1;then owner=caddy:caddy;fi;run "Set Pterodactyl ownership ($owner)" root chown -R "$owner" "$PTERODACTYL_DIRECTORY/";run 'Restart queue workers' php artisan queue:restart;run 'Exit maintenance mode' php artisan up;rm -rf "$work"; }
uninstall(){ preflight;[[ -f "$PTERODACTYL_DIRECTORY/.env" ]]||die 'No .env found. Refusing to risk APP_KEY/panel data.';warn 'Full web-directory backup + separate .env backup will be created first.';warn 'Keep a database backup too; the database is not contained in the web directory.';ask 'Create backup and continue?'||return;backup;printf '\n%sType UNINSTALL to continue:%s ' "$RED" "$RESET";read -r phrase;[[ $phrase == UNINSTALL ]]||{ warn 'Cancelled.';return;};restore_panel;ok "Blueprint removed and Pterodactyl restored in $PTERODACTYL_DIRECTORY"; }
reinstall(){ preflight;warn 'Blueprint reinstall does not intentionally delete .env or the panel database.';ask 'Continue?'||return;install; }
repair(){ preflight;packages;node_setup;configure;cd "$PTERODACTYL_DIRECTORY";run 'Install/repair Yarn dependencies' yarn install;[[ ! -f blueprint.sh ]]||run 'Fix blueprint.sh permission' root chmod +x blueprint.sh;ok 'Repair complete'; }
doctor(){ preflight;printf '\nPHP: ';exists php&&php -v|head -1||echo missing;printf 'Composer: ';exists composer&&composer --version|head -1||echo missing;printf 'Node: ';exists node&&node -v||echo missing;printf 'npm: ';exists npm&&npm -v||echo missing;printf 'Yarn: ';exists yarn&&yarn -v||echo missing;printf 'Blueprint: ';exists blueprint&&echo available||echo missing;[[ -f "$PTERODACTYL_DIRECTORY/.env" ]]&&ok '.env present'||warn '.env missing';[[ -f "$PTERODACTYL_DIRECTORY/.blueprintrc" ]]&&ok '.blueprintrc present'||warn '.blueprintrc missing'; }
config(){ preflight;printf '\nPterodactyl directory : %s\nBlueprint release URL : %s\nBackup directory      : %s\nLog file              : %s\n' "$PTERODACTYL_DIRECTORY" "$BLUEPRINT_RELEASE_URL" "$BACKUP_ROOT" "$LOG_FILE";[[ -f "$PTERODACTYL_DIRECTORY/.blueprintrc" ]]&&{ echo;cat "$PTERODACTYL_DIRECTORY/.blueprintrc";}; }
dryrun(){ preflight;cat <<EOF

DRY RUN — no changes will be made.
Install: dependencies → Node.js 22 → Blueprint release → .blueprintrc → yarn install.
Blueprint update: stable / remote / custom fork.
Uninstall: full web backup → separate .env → maintenance mode → replace panel → restore .env → composer → caches → migrations → ownership → queue restart → panel up.
Backup: $BACKUP_ROOT
EOF
}
menu(){ while true;do banner;cat <<'EOF'
╭──────────────────────────────────────────────────────────╮
│ ROOTSUNNYLAB • BLUEPRINT INSTALLER                       │
├──────────────────────────────────────────────────────────┤
│  1  Install Blueprint                                    │
│  2  Update Blueprint                                     │
│  3  Reinstall Blueprint                                  │
│  4  Repair Installation                                  │
│  5  Check System / Doctor                                │
│  6  Show Configuration                                   │
│  7  Uninstall Blueprint + Restore Pterodactyl            │
│  8  Full Backup                                          │
│  9  Dry Run / Preview                                    │
│ 10  View Installer Log                                   │
│  0  Exit                                                 │
╰──────────────────────────────────────────────────────────╯
EOF
read -r -p 'Select an option [0-10]: ' c;case $c in 1)install;;2)update;;3)reinstall;;4)repair;;5)doctor;;6)config;;7)uninstall;;8)preflight;backup;;9)dryrun;;10)tail -n 100 "$LOG_FILE" 2>/dev/null||true;;0)exit 0;;*)warn 'Invalid selection.';;esac;echo;read -r -p 'Press Enter to continue...' _;done; }
case ${1:-} in --install)install;;--update)update;;--reinstall)reinstall;;--repair)repair;;--doctor)doctor;;--config)config;;--uninstall)uninstall;;--backup)preflight;backup;;--dry-run)dryrun;;--version)echo "$VERSION";;--help|-h)echo "ROOTSUNNYLAB Blueprint Installer $VERSION";echo "Usage: $0 [--install|--update|--reinstall|--repair|--doctor|--config|--uninstall|--backup|--dry-run]";;*)menu;;esac
