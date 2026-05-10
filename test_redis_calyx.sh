#!/bin/bash
echo "🔴 CALYX REALTIME MOCK DATA DEMO"
echo "================================"

# Generate mock data
echo "Generating mock data for user 100..."
curl -s "http://localhost:8080/mock/generate?user_id=100&count=5" | jq '{user, metrics_generated: .metrics.generated, traces_generated: .traces.generated}'

# Generate metrics batch
echo -e "\nGenerating 20 random metrics..."
curl -s "http://localhost:8080/mock/metrics?count=20" | jq .

# Check stats
echo -e "\nCurrent system stats:"
curl -s "http://localhost:8080/mock/stats" | jq .

# Verify with FSM
echo -e "\nVerifying user 100 state:"
curl -s "http://localhost:8080/fsm/?user_id=100&event=login_attempt" | jq '{state, effects_executed}'

echo -e "\n✅ Real-time mock data generation working!"
