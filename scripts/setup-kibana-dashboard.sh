#!/bin/bash
# setup-kibana-dashboard.sh
# Creates a saved Kibana dashboard for the TrustMeBro lab.
# Run from any machine with curl access to the Elastic stack.
#
# Usage: ./scripts/setup-kibana-dashboard.sh [ELASTIC_IP] [ELASTIC_PASS]

set -e

ELASTIC_IP="${1:-10.1.10.10}"
ELASTIC_PASS="${2:-TrustMeBro2026!}"
KIBANA_URL="https://${ELASTIC_IP}:5601"
AUTH="elastic:${ELASTIC_PASS}"

echo "[*] Setting up TrustMeBro Lab dashboard on ${KIBANA_URL}"

# Wait for Kibana to be ready
echo "[*] Waiting for Kibana..."
for i in $(seq 1 30); do
    if curl -sk -u "${AUTH}" "${KIBANA_URL}/api/status" | grep -q '"overall"'; then
        echo "[+] Kibana is ready"
        break
    fi
    sleep 5
done

# Create saved search: Process Creation Events
echo "[*] Creating saved searches..."
curl -sk -u "${AUTH}" -X POST "${KIBANA_URL}/api/saved_objects/search/trustmebro-process-events" \
  -H 'kbn-xsrf: true' \
  -H 'Content-Type: application/json' \
  -d '{
  "attributes": {
    "title": "TrustMeBro: Process Creation",
    "description": "Process creation events for lab monitoring",
    "kibanaSavedObjectMeta": {
      "searchSourceJSON": "{\"query\":{\"query\":\"event.category: process AND event.action: start\",\"language\":\"kuery\"},\"filter\":[],\"indexRefName\":\"kibanaSavedObjectMeta.searchSourceJSON.index\"}"
    }
  },
  "references": []
}' 2>/dev/null && echo " [+] Process creation search created"

# Create saved search: Registry Modification Events
curl -sk -u "${AUTH}" -X POST "${KIBANA_URL}/api/saved_objects/search/trustmebro-registry-events" \
  -H 'kbn-xsrf: true' \
  -H 'Content-Type: application/json' \
  -d '{
  "attributes": {
    "title": "TrustMeBro: Registry Modifications",
    "description": "Registry modification events relevant to SIP and trust provider hijacking",
    "kibanaSavedObjectMeta": {
      "searchSourceJSON": "{\"query\":{\"query\":\"event.category: registry AND (registry.path: *Cryptography* OR registry.path: *Trust* OR registry.path: *SoftwarePublishing*)\",\"language\":\"kuery\"},\"filter\":[],\"indexRefName\":\"kibanaSavedObjectMeta.searchSourceJSON.index\"}"
    }
  },
  "references": []
}' 2>/dev/null && echo " [+] Registry modification search created"

# Set default time range to last 15 minutes via advanced settings
echo "[*] Setting default time range to 15 minutes..."
curl -sk -u "${AUTH}" -X POST "${KIBANA_URL}/api/kibana/settings" \
  -H 'kbn-xsrf: true' \
  -H 'Content-Type: application/json' \
  -d '{
  "changes": {
    "timepicker:timeDefaults": "{\"from\":\"now-15m\",\"to\":\"now\"}"
  }
}' 2>/dev/null && echo " [+] Default time range set to 15 minutes"

# Set dark mode (easier on projectors)
echo "[*] Setting dark mode..."
curl -sk -u "${AUTH}" -X POST "${KIBANA_URL}/api/kibana/settings" \
  -H 'kbn-xsrf: true' \
  -H 'Content-Type: application/json' \
  -d '{
  "changes": {
    "theme:darkMode": true
  }
}' 2>/dev/null && echo " [+] Dark mode enabled"

echo ""
echo "[+] Dashboard setup complete."
echo "    Open: ${KIBANA_URL}/app/security/overview"
echo "    Alerts: ${KIBANA_URL}/app/security/alerts"
echo ""
echo "    The Elastic Security app has built-in dashboards for:"
echo "    - Security alerts (auto-populated by Elastic Defend)"
echo "    - Process events"
echo "    - Registry events"
echo "    - File events"
echo ""
echo "    Default time window is now 15 minutes."
echo "    Students open Edge on any Windows machine and land on Kibana."
