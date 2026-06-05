#!/bin/bash
# Usage: export DD_API_KEY="your_api_key_here"
#        chmod a+x /path/sysmon.sh
#        ./sysmon.sh 

# --- CONFIGURATION ---
MEM_THRESHOLD_PERCENT=40
WEB_SERVICES="nginx apache2 lighttpd"

echo "=== SYSTEM MONITORING REPORT | $(date) ==="
echo ""

# =========================================================================
# DATADOG TELEMETRY INJECTION ENGINE
# =========================================================================
# This reusable function handles sending structured events straight to your cloud app via API
send_datadog_event() {
    local TITLE="$1"
    local TEXT="$2"
    local ALERT_TYPE="$3" # can be: error, warning, info, success

    # Only attempt to ship logs if you have configured an API key
    if [ -n "$DD_API_KEY" ]; then
        curl -X POST "https://api.datadoghq.com/api/v1/events" \
        -s -o /dev/null \
        -H "Content-Type: application/json" \
        -H "DD-API-KEY: ${DD_API_KEY}" \
        -d @- <<EOF
{
  "title": "${TITLE}",
  "text": "${TEXT}",
  "priority": "normal",
  "tags": ["environment:devops-lab", "module:1", "host:debian13", "script:sysmon"],
  "alert_type": "${ALERT_TYPE}"
}
EOF
    fi
}
# =========================================================================

# 0. CHECKING SYSTEM WEB SERVICES
# Get all the services in the system

echo "[SYSTEM WEB SERVICES STATUS]"
FOUND_ANY_SERVICE=false

for SERVICE in $WEB_SERVICES; do
    # Check if the service unit file even exists on the system
    if systemctl list-unit-files | grep -q "^${SERVICE}.service"; then
        FOUND_ANY_SERVICE=true
        # Check if the service is actively running
        if systemctl is-active --quiet "$SERVICE"; then
            echo "✅ $SERVICE: Running smoothly."
        else
            echo "❌ $SERVICE: NOT RUNNING! (Attempting to check status...)"
            systemctl status "$SERVICE" | grep "Active:" | awk '{print "   -> Status "$0}'
            
            # --- DATADOG INJECTION PLACE 1 ---
            send_datadog_event "Service Failure: $SERVICE" "The web service tracking agent detected that $SERVICE is stopped on debian13." "error"
        fi
    fi
done

if [ "$FOUND_ANY_SERVICE" = false ]; then
    echo "ℹ️ INFO: No standard web services ($WEB_SERVICES) are installed on this system."
fi
echo "----------------------------------------"



# 1. CPU IDLE STATES
# Grabs the idle percentage from top
CPU_IDLE=$(top -bn1 | grep "Cpu(s)" | awk '{print $8}')
echo "[CPU STATUS]"
echo "Current CPU Idle State: $CPU_IDLE%"

# Compare floating point numbers using bc
if (( $(echo "$CPU_IDLE < 100.0" | bc -l) )); then
    echo "⚠️ WARNING: CPU idle state is dangerously low! High processing load."
    
    # --- DATADOG INJECTION PLACE 2 ---
    send_datadog_event "Resource Alert: Low CPU Idle" "CPU idle headroom is dangerously low at ${CPU_IDLE}%." "warning"
else
    echo "✅ OK: CPU idle headroom is sufficient."
fi
echo "----------------------------------------"

# 2. ACTIVE MEMORY THRESHOLDS
# Calculates active memory usage percentage
MEM_TOTAL=$(free | grep Mem | awk '{print $2}')
MEM_USED=$(free | grep Mem | awk '{print $3}')
MEM_USAGE_PERCENT=$(( 100 * MEM_USED / MEM_TOTAL ))

echo "[MEMORY STATUS]"
echo "Memory Usage: $MEM_USAGE_PERCENT% ($((MEM_USED / 1024))MB used of $((MEM_TOTAL / 1024))MB total)"

if [ "$MEM_USAGE_PERCENT" -gt "$MEM_THRESHOLD_PERCENT" ]; then
    echo "⚠️ WARNING: Active memory usage has breached the $MEM_THRESHOLD_PERCENT% threshold!"
    
    # --- DATADOG INJECTION PLACE 3 ---
    send_datadog_event "Resource Alert: High Memory Usage" "Active memory usage has breached safe operational baselines. Currently at ${MEM_USAGE_PERCENT}%." "warning"
else
    echo "✅ OK: Memory usage is within safe parameters."
fi
echo "----------------------------------------"

# 3.NETWORK MONITOR (HTTP & SSH)
# use the ss command for monitoring

echo "[NETWORK TRAFFIC STATUS ]"

# Count active connections using 'ss'
SSH_CONN=$(ss -atn sport = :22 or dport = :22 | grep -c ESTAB)
HTTP_CONN=$(ss -atn sport = :80 or dport = :80 or sport = :443 or dport = :443 | grep -c ESTAB)

echo "Active SSH (Port 22) connections: $SSH_CONN"
echo "Active HTTP/S (Port 80/443) connections: $HTTP_CONN"

# Check if services are listening
if ! ss -ltn | grep -q :22; then
    echo "⚠️ ALERT: SSH service is NOT listening on port 22!"
    
    # --- DATADOG INJECTION PLACE 4 ---
    send_datadog_event "Security Alert: SSH Port Closed" "Telemetric probe detected that port 22 is no longer accepting connection states." "error"
fi

if ! ss -ltn | grep -E -q ':(80|443)'; then
    echo "ℹ️ INFO: No web server listening on ports 80 or 443."
fi
echo "----------------------------------------"


# 4. FIREWALL LOG ANOMALIES
# Uses native Debian 13 journalctl instead of legacy log files
echo "[FIREWALL SECURITY STATUS]"

# Count UFW block/drop actions from the last hour
BLOCKED_COUNT=$(sudo journalctl -k -g "UFW" --since "1 hour ago" 2>/dev/null | grep -c -E "BLOCK|DROP|REJECT")

# Fallback if variable is empty
if [ -z "$BLOCKED_COUNT" ]; then
    BLOCKED_COUNT=0
fi

echo "Blocked connections detected in the last hour: $BLOCKED_COUNT"

if [ "$BLOCKED_COUNT" -gt 0 ]; then
    echo "Recent blocked connection events (Last 5):"

    # Parse the journal strings dynamically for Source IP and Target Port
    sudo journalctl -k -g "UFW" --since "1 hour ago" 2>/dev/null | grep -E "BLOCK|DROP|REJECT" | tail -n 5 | awk '{
        src="UNKNOWN"; dpt="UNKNOWN";
        for(i=1;i<=NF;i++) {
            if($i ~ /^SRC=/) src=substr($i,5);
            if($i ~ /^DPT=/) dpt=substr($i,5);
        }
        print " -> Time: "$1" "$2" "$3" | Source IP: "src" | Port: "dpt
    }'
    
    # --- DATADOG INJECTION PLACE 5 ---
    if [ "$BLOCKED_COUNT" -gt 50 ]; then
        send_datadog_event "Security Warning: UFW Network Blocks Spike" "Firewall state evaluation detected ${BLOCKED_COUNT} block events within the last hour window." "warning"
    fi
else
    echo "✅ OK: No recent firewall blocks detected."
fi
echo "========================================"
