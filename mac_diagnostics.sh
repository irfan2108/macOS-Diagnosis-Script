#!/bin/bash
#
# mac_diagnostics.sh
# ---------------------------------------------------------------
# A comprehensive macOS diagnostic script.
# Collects system, hardware, network, storage, software, security,
# and backup health information into a readable report.
#
# Usage:
#   chmod +x mac_diagnostics.sh
#   ./mac_diagnostics.sh                          # plain text report (default)
#   ./mac_diagnostics.sh --format json            # JSON report
#   ./mac_diagnostics.sh --format csv             # CSV report
#   ./mac_diagnostics.sh --format all             # txt + json + csv
#   ./mac_diagnostics.sh --apps "Slack,Docker,Figma"   # check specific app versions
#   sudo ./mac_diagnostics.sh                     # fuller report (SMART, some protected info)
#
# Options:
#   --format text|json|csv|all   Output format (default: text)
#   --apps "App1,App2,..."       Comma-separated app names to version-check
#                                 (must match the .app name in /Applications, no ".app")
#   -h, --help                   Show this help
# ---------------------------------------------------------------

set -o pipefail

# ---------- Argument parsing ----------
FORMAT="text"
APPS=""

print_help() {
    grep '^#' "$0" | sed 's/^#//'
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --format)
            FORMAT="$2"; shift 2 ;;
        --format=*)
            FORMAT="${1#*=}"; shift ;;
        --apps)
            APPS="$2"; shift 2 ;;
        --apps=*)
            APPS="${1#*=}"; shift ;;
        -h|--help)
            print_help; exit 0 ;;
        *)
            echo "Unknown option: $1"
            print_help
            exit 1 ;;
    esac
done

case "$FORMAT" in
    text|json|csv|all) ;;
    *) echo "Invalid --format '$FORMAT'. Use text, json, csv, or all."; exit 1 ;;
esac

# ---------- Setup ----------
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
REPORT_DIR="$HOME/Desktop/Mac_Diagnostics"
BASE="$REPORT_DIR/diagnostic_report_$TIMESTAMP"
TXT_FILE="$BASE.txt"
JSON_FILE="$BASE.json"
CSV_FILE="$BASE.csv"
mkdir -p "$REPORT_DIR"

# Colors for console output
BOLD=$(tput bold 2>/dev/null)
RESET=$(tput sgr0 2>/dev/null)
GREEN=$(tput setaf 2 2>/dev/null)
YELLOW=$(tput setaf 3 2>/dev/null)
RED=$(tput setaf 1 2>/dev/null)
CYAN=$(tput setaf 6 2>/dev/null)

# Holds structured key=value pairs for JSON/CSV export
FIELDS=()

command_exists() { command -v "$1" >/dev/null 2>&1; }

# Print to console always; append to the .txt file only if that format was requested
log() {
    echo -e "$1"
    if [[ "$FORMAT" == "text" || "$FORMAT" == "all" ]]; then
        echo -e "$1" >> "$TXT_FILE"
    fi
}

section() { log "\n${BOLD}${CYAN}==================== $1 ====================${RESET}"; }
ok()   { log "${GREEN}[OK]${RESET} $1"; }
warn() { log "${YELLOW}[WARN]${RESET} $1"; }
err()  { log "${RED}[ISSUE]${RESET} $1"; }

# Store a structured field (used to build JSON/CSV). Newlines are flattened.
record() {
    local key="$1" value="$2"
    value="${value//$'\n'/; }"
    FIELDS+=("$key=$value")
}

sanitize_key() {
    echo "$1" | tr '[:upper:]' '[:lower:]' | tr -c '[:alnum:]' '_' | sed 's/_\{2,\}/_/g;s/^_//;s/_$//'
}

# ---------- Header ----------
log "${BOLD}macOS Diagnostic Report${RESET}"
log "Generated: $(date)"
record "report_generated" "$(date)"

# ---------- 1. System Information ----------
section "System Information"
HOSTNAME=$(scutil --get ComputerName 2>/dev/null)
MACOS_VER=$(sw_vers -productVersion)
MACOS_BUILD=$(sw_vers -buildVersion)
MACOS_NAME=$(sw_vers -productName)
UPTIME=$(uptime | sed 's/.*up //;s/,.*load.*//')
BOOT_VOL=$(diskutil info / 2>/dev/null | awk -F': ' '/Volume Name/{print $2}')

log "Hostname:            $HOSTNAME"
log "macOS Version:       $MACOS_VER (Build $MACOS_BUILD)"
log "macOS Name:          $MACOS_NAME"
log "Kernel Version:      $(uname -v)"
log "Uptime:              $UPTIME"
log "Boot Volume:         $BOOT_VOL"

record "hostname" "$HOSTNAME"
record "macos_version" "$MACOS_VER"
record "macos_build" "$MACOS_BUILD"
record "macos_name" "$MACOS_NAME"
record "uptime" "$UPTIME"
record "boot_volume" "$BOOT_VOL"

# ---------- 2. Hardware Information ----------
section "Hardware Information"
MODEL=$(sysctl -n hw.model 2>/dev/null)
CHIP=$(sysctl -n machdep.cpu.brand_string 2>/dev/null)
if [ -z "$CHIP" ]; then
    CHIP=$(system_profiler SPHardwareDataType 2>/dev/null | awk -F': ' '/Chip/{print $2}')
fi
SERIAL=$(system_profiler SPHardwareDataType 2>/dev/null | awk -F': ' '/Serial Number/{print $2}')
RAM=$(sysctl -n hw.memsize 2>/dev/null | awk '{printf "%.0f GB", $1/1024/1024/1024}')
CORES=$(sysctl -n hw.ncpu 2>/dev/null)

log "Model Identifier:    $MODEL"
log "Chip / CPU:          $CHIP"
log "Serial Number:       $SERIAL"
log "Total RAM:           $RAM"
log "CPU Cores:           $CORES"

record "model_identifier" "$MODEL"
record "chip" "$CHIP"
record "serial_number" "$SERIAL"
record "ram_total" "$RAM"
record "cpu_cores" "$CORES"

# ---------- 3. Battery Health ----------
section "Battery Health"
if system_profiler SPPowerDataType 2>/dev/null | grep -q "Battery Information"; then
    BATT_CYCLES=$(system_profiler SPPowerDataType 2>/dev/null | awk -F': ' '/Cycle Count/{print $2}')
    BATT_CONDITION=$(system_profiler SPPowerDataType 2>/dev/null | awk -F': ' '/Condition/{print $2}')
    BATT_MAX=$(system_profiler SPPowerDataType 2>/dev/null | awk -F': ' '/Maximum Capacity/{print $2}')
    log "Cycle Count:         $BATT_CYCLES"
    log "Condition:           $BATT_CONDITION"
    log "Maximum Capacity:    $BATT_MAX"
    record "battery_cycle_count" "$BATT_CYCLES"
    record "battery_condition" "$BATT_CONDITION"
    record "battery_max_capacity" "$BATT_MAX"
else
    log "No battery detected (likely a desktop Mac)."
    record "battery" "not_present"
fi

# ---------- 4. Storage / Disk Health ----------
section "Storage & Disk Health"
DISK_USED=$(df -H / | tail -1 | awk '{print $3}')
DISK_TOTAL=$(df -H / | tail -1 | awk '{print $2}')
DISK_FULL_PCT=$(df / | tail -1 | awk '{gsub("%","",$5); print $5}')
log "Disk Usage:          $DISK_USED used / $DISK_TOTAL total (${DISK_FULL_PCT}% full)"
record "disk_used" "$DISK_USED"
record "disk_total" "$DISK_TOTAL"
record "disk_percent_full" "$DISK_FULL_PCT"

DISK_ID=$(diskutil info / 2>/dev/null | awk -F': ' '/Device Node/{print $2}' | tr -d ' ')
SMART="unknown"
if [ -n "$DISK_ID" ]; then
    SMART=$(diskutil info "$DISK_ID" 2>/dev/null | awk -F': ' '/SMART Status/{print $2}' | tr -d ' ')
    if [ "$SMART" = "Verified" ]; then
        ok "SMART Status: $SMART (drive healthy)"
    elif [ -n "$SMART" ]; then
        err "SMART Status: $SMART -- drive may be failing, back up immediately"
    else
        warn "SMART status unavailable (common on Apple Silicon internal SSDs / needs sudo)"
        SMART="unavailable"
    fi
fi
record "smart_status" "$SMART"

if [ "$DISK_FULL_PCT" -ge 90 ] 2>/dev/null; then
    err "Startup disk is ${DISK_FULL_PCT}% full -- free up space to avoid slowdowns"
elif [ "$DISK_FULL_PCT" -ge 75 ] 2>/dev/null; then
    warn "Startup disk is ${DISK_FULL_PCT}% full -- consider cleaning up soon"
else
    ok "Startup disk usage looks healthy (${DISK_FULL_PCT}% full)"
fi

# ---------- 5. Memory Pressure ----------
section "Memory Pressure"
if command_exists memory_pressure; then
    MP=$(memory_pressure 2>/dev/null | tail -1)
    log "$MP"
    record "memory_pressure" "$MP"
else
    MP=$(vm_stat | head -6)
    log "$MP"
    record "memory_pressure_raw" "$MP"
fi

# ---------- 6. Network Information ----------
section "Network Information"
ACTIVE_IF=$(route get default 2>/dev/null | awk '/interface:/{print $2}')
LOCAL_IP=$(ipconfig getifaddr "$ACTIVE_IF" 2>/dev/null)
MAC_ADDR=$(ifconfig "$ACTIVE_IF" 2>/dev/null | awk '/ether/{print $2}')
GATEWAY=$(route -n get default 2>/dev/null | awk '/gateway:/{print $2}')
DNS_SERVERS=$(scutil --dns 2>/dev/null | awk '/nameserver\[0\]/{print $3}' | sort -u | tr '\n' ' ')

log "Active Interface:    $ACTIVE_IF"
log "Local IP Address:    $LOCAL_IP"
log "MAC Address:         $MAC_ADDR"
log "Router / Gateway:    $GATEWAY"
log "DNS Servers:         $DNS_SERVERS"

record "active_interface" "$ACTIVE_IF"
record "local_ip" "$LOCAL_IP"
record "mac_address" "$MAC_ADDR"
record "gateway" "$GATEWAY"
record "dns_servers" "$DNS_SERVERS"

if [[ "$ACTIVE_IF" == en0 ]] && command_exists networksetup; then
    WIFI_INFO=$(networksetup -getairportnetwork "$ACTIVE_IF" 2>/dev/null)
    WIFI_NAME="${WIFI_INFO#Current Wi-Fi Network: }"
    log "Wi-Fi Network:       $WIFI_NAME"
    record "wifi_network" "$WIFI_NAME"
fi

PUBLIC_IP=$(curl -s --max-time 3 https://ifconfig.me 2>/dev/null)
if [ -n "$PUBLIC_IP" ]; then
    log "Public IP Address:   $PUBLIC_IP"
else
    warn "Could not reach the internet to determine public IP"
    PUBLIC_IP="unreachable"
fi
record "public_ip" "$PUBLIC_IP"

if ping -c 1 -t 2 8.8.8.8 >/dev/null 2>&1; then
    ok "Internet connectivity: reachable"
    record "internet_reachable" "true"
else
    err "Internet connectivity: unreachable"
    record "internet_reachable" "false"
fi

# ---------- 7. MDM / Enrollment Status ----------
section "MDM / Device Enrollment Status"
if command_exists profiles; then
    ENROLL=$(profiles status -type enrollment 2>/dev/null)
    if [ -n "$ENROLL" ]; then
        log "$ENROLL"
        record "mdm_enrollment_status" "$ENROLL"
    else
        warn "Could not read enrollment status (may need sudo)"
        record "mdm_enrollment_status" "unknown_needs_sudo"
    fi
else
    warn "'profiles' command not found"
    record "mdm_enrollment_status" "profiles_command_missing"
fi

# ---------- 8. Software Update Status ----------
section "Software Update Status"
SOFTWARE_UPDATES=$(softwareupdate -l 2>&1)
if echo "$SOFTWARE_UPDATES" | grep -q "No new software available"; then
    ok "macOS is up to date"
    record "software_updates_pending" "none"
else
    UPDATE_LINES=$(echo "$SOFTWARE_UPDATES" | tail -n +2)
    warn "Updates may be available:"
    log "$UPDATE_LINES"
    record "software_updates_pending" "$UPDATE_LINES"
fi

# ---------- 9. Firewall & Gatekeeper ----------
section "Firewall & Gatekeeper"
FW_STATE_RAW=$(defaults read /Library/Preferences/com.apple.alf globalstate 2>/dev/null)
case "$FW_STATE_RAW" in
    0) FW_STATE="Off" ;;
    1) FW_STATE="On (specific services)" ;;
    2) FW_STATE="On (essential services only)" ;;
    *) FW_STATE="Unknown (try running with sudo)" ;;
esac
if [ "$FW_STATE_RAW" = "0" ]; then
    warn "Firewall: $FW_STATE"
else
    ok "Firewall: $FW_STATE"
fi
record "firewall_state" "$FW_STATE"

if command_exists spctl; then
    GK_STATUS=$(spctl --status 2>&1)
    if echo "$GK_STATUS" | grep -qi "enabled"; then
        ok "Gatekeeper: $GK_STATUS"
    else
        warn "Gatekeeper: $GK_STATUS"
    fi
    record "gatekeeper_status" "$GK_STATUS"
else
    warn "'spctl' command not found"
    record "gatekeeper_status" "spctl_missing"
fi

# ---------- 10. Time Machine ----------
section "Time Machine"
if command_exists tmutil; then
    TM_DEST=$(tmutil destinationinfo 2>/dev/null)
    if [ -n "$TM_DEST" ]; then
        log "$TM_DEST"
        record "time_machine_destination" "$TM_DEST"
    else
        warn "No Time Machine destination configured"
        record "time_machine_destination" "none_configured"
    fi

    LATEST_BACKUP=$(tmutil latestbackup 2>/dev/null)
    if [ -n "$LATEST_BACKUP" ]; then
        BACKUP_DATE_STR=$(basename "$LATEST_BACKUP" | sed -E 's/\.backup$//')
        log "Latest Backup:       $BACKUP_DATE_STR"
        record "time_machine_latest_backup" "$BACKUP_DATE_STR"

        BACKUP_EPOCH=$(date -j -f "%Y-%m-%d-%H%M%S" "$BACKUP_DATE_STR" "+%s" 2>/dev/null)
        NOW_EPOCH=$(date "+%s")
        if [ -n "$BACKUP_EPOCH" ]; then
            AGE_DAYS=$(( (NOW_EPOCH - BACKUP_EPOCH) / 86400 ))
            if [ "$AGE_DAYS" -le 2 ]; then
                ok "Last backup was $AGE_DAYS day(s) ago"
            elif [ "$AGE_DAYS" -le 7 ]; then
                warn "Last backup was $AGE_DAYS day(s) ago -- consider backing up soon"
            else
                err "Last backup was $AGE_DAYS day(s) ago -- backups are overdue"
            fi
            record "time_machine_backup_age_days" "$AGE_DAYS"
        fi
    else
        warn "No completed Time Machine backups found (or Time Machine not in use)"
        record "time_machine_latest_backup" "none_found"
    fi
else
    warn "'tmutil' command not found"
fi

# ---------- 11. Application Versions ----------
section "Application Versions"
if [ -n "$APPS" ]; then
    IFS=',' read -ra APP_ARRAY <<< "$APPS"
else
    APP_ARRAY=("Safari" "Google Chrome" "Firefox" "Slack" "zoom.us" "Microsoft Word" "Visual Studio Code" "Docker")
fi

for APP in "${APP_ARRAY[@]}"; do
    APP_TRIMMED=$(echo "$APP" | sed 's/^ *//;s/ *$//')
    APP_PATH="/Applications/$APP_TRIMMED.app/Contents/Info"
    if [ -f "/Applications/$APP_TRIMMED.app/Contents/Info.plist" ]; then
        VERSION=$(defaults read "$APP_PATH" CFBundleShortVersionString 2>/dev/null)
        BUILD=$(defaults read "$APP_PATH" CFBundleVersion 2>/dev/null)
        log "$APP_TRIMMED: $VERSION (build $BUILD)"
        record "app_version_$(sanitize_key "$APP_TRIMMED")" "$VERSION (build $BUILD)"
    else
        log "$APP_TRIMMED: not installed"
        record "app_version_$(sanitize_key "$APP_TRIMMED")" "not_installed"
    fi
done

# ---------- 12. Recent Crashes & Kernel Panics ----------
section "Recent Crashes & Kernel Panics"
CRASH_DIR="$HOME/Library/Logs/DiagnosticReports"
if [ -d "$CRASH_DIR" ]; then
    RECENT_CRASHES=$(find "$CRASH_DIR" -type f -mtime -7 \( -name "*.crash" -o -name "*.ips" \) 2>/dev/null)
    PANIC_COUNT=$(echo "$RECENT_CRASHES" | grep -ci "panic")
    CRASH_COUNT=$(echo "$RECENT_CRASHES" | grep -vi "panic" | grep -c .)

    if [ "$PANIC_COUNT" -gt 0 ]; then
        err "$PANIC_COUNT kernel panic report(s) found in the last 7 days"
    else
        ok "No kernel panics in the last 7 days"
    fi
    record "kernel_panics_last_7_days" "$PANIC_COUNT"

    if [ "$CRASH_COUNT" -gt 0 ]; then
        warn "$CRASH_COUNT application crash report(s) in the last 7 days"
        CRASH_FILES=$(echo "$RECENT_CRASHES" | grep -vi "panic" | grep . | head -5 | xargs -n1 basename 2>/dev/null | tr '\n' ',')
        log "  Recent: $CRASH_FILES"
        record "recent_crash_files" "$CRASH_FILES"
    else
        ok "No application crashes in the last 7 days"
    fi
    record "app_crashes_last_7_days" "$CRASH_COUNT"
else
    log "No DiagnosticReports directory found."
fi

# ---------- 13. Top Resource-Heavy Processes ----------
section "Top CPU-Consuming Processes"
TOP_CPU=$(ps -Arco pid,%cpu,%mem,comm -r | head -6)
log "$TOP_CPU"
record "top_cpu_processes" "$TOP_CPU"

section "Top Memory-Consuming Processes"
TOP_MEM=$(ps -Arco pid,%cpu,%mem,comm -m | head -6)
log "$TOP_MEM"
record "top_memory_processes" "$TOP_MEM"

# ---------- 14. Login Items / Launch Agents ----------
section "Login Items & Launch Agents"
LOGIN_ITEMS=$(osascript -e 'tell application "System Events" to get the name of every login item' 2>/dev/null)
log "Login Items: ${LOGIN_ITEMS:-none found or permission denied}"
record "login_items" "${LOGIN_ITEMS:-none}"

USER_AGENTS_DIR="$HOME/Library/LaunchAgents"
if [ -d "$USER_AGENTS_DIR" ]; then
    COUNT=$(find "$USER_AGENTS_DIR" -name "*.plist" 2>/dev/null | wc -l | tr -d ' ')
    log "User LaunchAgents installed: $COUNT"
    record "user_launch_agents_count" "$COUNT"
fi

# ---------- Export structured formats ----------
write_json() {
    {
        echo "{"
        local n=${#FIELDS[@]}
        local i=0
        for entry in "${FIELDS[@]}"; do
            i=$((i+1))
            local key="${entry%%=*}"
            local value="${entry#*=}"
            value="${value//\\/\\\\}"
            value="${value//\"/\\\"}"
            if [ "$i" -lt "$n" ]; then
                printf '  "%s": "%s",\n' "$key" "$value"
            else
                printf '  "%s": "%s"\n' "$key" "$value"
            fi
        done
        echo "}"
    } > "$JSON_FILE"
}

write_csv() {
    {
        echo "Field,Value"
        for entry in "${FIELDS[@]}"; do
            local key="${entry%%=*}"
            local value="${entry#*=}"
            value="${value//\"/\"\"}"
            printf '"%s","%s"\n' "$key" "$value"
        done
    } > "$CSV_FILE"
}

if [[ "$FORMAT" == "json" || "$FORMAT" == "all" ]]; then
    write_json
fi
if [[ "$FORMAT" == "csv" || "$FORMAT" == "all" ]]; then
    write_csv
fi

# ---------- Footer ----------
section "Summary"
log "Diagnostic scan complete."
[[ "$FORMAT" == "text" || "$FORMAT" == "all" ]] && log "Text report saved at: ${BOLD}$TXT_FILE${RESET}"
[[ "$FORMAT" == "json" || "$FORMAT" == "all" ]] && log "JSON report saved at: ${BOLD}$JSON_FILE${RESET}"
[[ "$FORMAT" == "csv"  || "$FORMAT" == "all" ]] && log "CSV report saved at: ${BOLD}$CSV_FILE${RESET}"
log "Review any [WARN] or [ISSUE] lines above for items needing attention."
