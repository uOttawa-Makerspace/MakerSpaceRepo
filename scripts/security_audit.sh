#!/bin/bash
set -e

echo "Running Security Audit..."
echo ""

echo "=== 1. Brakeman (Static Analysis) ==="
bundle exec brakeman -w2

echo ""
echo "=== 2. Bundle Audit (Gem Vulnerabilities) ==="
bundle exec bundle-audit check --update

echo ""
echo "=== 3. Ruby Audit ==="
bundle exec ruby-audit check

echo ""
echo "=== 4. Checking for Outdated Gems ==="
bundle outdated --strict || true

echo ""
echo "Security Audit Complete"