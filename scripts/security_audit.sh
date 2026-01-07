# bin/security_audit

#!/bin/bash
echo "Running Security Audit..."
echo ""

echo "=== 1. Brakeman (Static Analysis) ==="
brakeman -q -w2

echo ""
echo "=== 2. Bundle Audit (Gem Vulnerabilities) ==="
bundle audit check --update

echo ""
echo "=== 3. Ruby Audit ==="
ruby-audit check

echo ""
echo "=== 4. Checking for Outdated Gems ==="
bundle outdated --strict

echo ""
echo "Security Audit Complete"