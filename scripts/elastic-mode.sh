#!/bin/bash
# Toggle Elastic Defend between Detect (alert-only) and Prevent (block) mode
#
# Usage:
#   ./elastic-mode.sh detect   # Alert only, no blocking
#   ./elastic-mode.sh prevent  # Block malicious activity
#   ./elastic-mode.sh status   # Show current mode
#
# Requires: curl, jq
# Reads ELASTIC_HOST and ELASTIC_PASS from environment or uses defaults.

ELASTIC_HOST="${ELASTIC_HOST:-https://10.1.10.10:5601}"
ELASTIC_PASS="${ELASTIC_PASS:-TrustMeBro2026!}"
ELASTIC_USER="${ELASTIC_USER:-elastic}"

CURL="curl -sk -u ${ELASTIC_USER}:${ELASTIC_PASS}"
API="${ELASTIC_HOST}/api"
HEADERS='-H "kbn-xsrf: true" -H "Content-Type: application/json"'

# Get the Elastic Defend integration policy ID
get_policy_id() {
    eval $CURL $HEADERS "${API}/fleet/package_policies?perPage=100" 2>/dev/null | \
        jq -r '.items[] | select(.package.name == "endpoint") | .id' | head -1
}

# Get current protection settings
get_status() {
    local pid=$(get_policy_id)
    if [ -z "$pid" ]; then
        echo "[-] No Elastic Defend policy found."
        exit 1
    fi

    local policy=$(eval $CURL $HEADERS "${API}/fleet/package_policies/${pid}" 2>/dev/null)
    local malware=$(echo "$policy" | jq -r '.item.inputs[0].config.policy.value.windows.malware.mode // "unknown"')
    local behavior=$(echo "$policy" | jq -r '.item.inputs[0].config.policy.value.windows.behavior_protection.mode // "unknown"')
    local memory=$(echo "$policy" | jq -r '.item.inputs[0].config.policy.value.windows.memory_protection.mode // "unknown"')
    local ransomware=$(echo "$policy" | jq -r '.item.inputs[0].config.policy.value.windows.ransomware.mode // "unknown"')

    echo "Elastic Defend Protection Status"
    echo "================================"
    echo "  Malware:           $malware"
    echo "  Behavior:          $behavior"
    echo "  Memory:            $memory"
    echo "  Ransomware:        $ransomware"
    echo ""
    if [ "$malware" = "prevent" ]; then
        echo "  Mode: PREVENT (blocking active)"
    else
        echo "  Mode: DETECT (alert only, no blocking)"
    fi
}

# Set all protection modes
set_mode() {
    local mode="$1"
    local pid=$(get_policy_id)
    if [ -z "$pid" ]; then
        echo "[-] No Elastic Defend policy found."
        exit 1
    fi

    # Get current policy
    local policy=$(eval $CURL $HEADERS "${API}/fleet/package_policies/${pid}" 2>/dev/null)
    local current=$(echo "$policy" | jq '.item')

    # Build the updated policy with all protections set to the target mode
    local updated=$(echo "$current" | jq --arg m "$mode" '
        .inputs[0].config.policy.value.windows.malware.mode = $m |
        .inputs[0].config.policy.value.windows.behavior_protection.mode = $m |
        .inputs[0].config.policy.value.windows.memory_protection.mode = $m |
        .inputs[0].config.policy.value.windows.ransomware.mode = $m |
        .inputs[0].config.policy.value.mac.malware.mode = $m |
        .inputs[0].config.policy.value.mac.behavior_protection.mode = $m |
        .inputs[0].config.policy.value.mac.memory_protection.mode = $m |
        .inputs[0].config.policy.value.linux.malware.mode = $m |
        .inputs[0].config.policy.value.linux.behavior_protection.mode = $m |
        .inputs[0].config.policy.value.linux.memory_protection.mode = $m
    ')

    # Push the update
    local result=$(echo "$updated" | eval $CURL $HEADERS -X PUT "${API}/fleet/package_policies/${pid}" -d @- 2>/dev/null)
    local success=$(echo "$result" | jq -r '.item.id // empty')

    if [ -n "$success" ]; then
        echo "[+] Elastic Defend set to: ${mode^^}"
        echo ""
        if [ "$mode" = "detect" ]; then
            echo "    All protections are in alert-only mode."
            echo "    Malicious activity generates alerts but is NOT blocked."
            echo "    Switch to prevent: ./elastic-mode.sh prevent"
        else
            echo "    All protections are actively blocking."
            echo "    Malicious activity will be terminated."
            echo "    Switch to detect: ./elastic-mode.sh detect"
        fi
    else
        echo "[-] Failed to update policy."
        echo "$result" | jq '.message // .error // .' 2>/dev/null
    fi
}

case "${1:-}" in
    detect|alert)
        set_mode "detect"
        ;;
    prevent|block)
        set_mode "prevent"
        ;;
    status|"")
        get_status
        ;;
    *)
        echo "Usage: $0 {detect|prevent|status}"
        echo ""
        echo "  detect   Alert only. No blocking. Good for demos."
        echo "  prevent  Active blocking. Stops malicious activity."
        echo "  status   Show current protection mode."
        exit 1
        ;;
esac
