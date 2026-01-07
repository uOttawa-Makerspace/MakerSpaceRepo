# bin/security_audit

#!/bin/bash
echo "Running Security Audit..."
echo ""

echo "=== Bundle Audit (Gem Vulnerabilities) ==="
bundle audit check --update

echo ""
echo "=== Ruby Audit ==="
ruby-audit check

echo ""
echo "=== Checking for Outdated Gems ==="
bundle outdated --strict

echo ""
echo "=== Brakeman (Static Analysis) ==="
brakeman -q -w2 --exit-on-warn

echo ""
echo "Security Audit Complete"