#!/usr/bin/env bash
# control: allowed_locations
# reference: allowed-locations
# Non-compliant: an empty NSG (free) in eastus. The subscription's own region policy
# may deny it too; the test only checks that bastion-baseline is among the deniers.
BASTION_TEST_NAME="allowed-locations"
# shellcheck source=tests/policy/lib.sh
source "$(dirname "$0")/lib.sh"

name="nsg-bt-loc-$(random_suffix)"
body="$(jq -nc --argjson tags "$(bastion_test_tags)" '{location: "eastus", tags: $tags, properties: {}}')"

expect_denied "Microsoft.Network/networkSecurityGroups" "$name" "2024-05-01" "$body" "allowed-locations"
