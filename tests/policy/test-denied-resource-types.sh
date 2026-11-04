#!/usr/bin/env bash
# control: denied_resource_types
# reference: denied-resource-types
# Non-compliant: a public IP address, one of the denied types.
# Cost if it wrongly succeeds: a Standard static public IP, about $0.005 an hour,
# deleted by the trap within a minute.
BASTION_TEST_NAME="denied-resource-types"
# shellcheck source=tests/policy/lib.sh
source "$(dirname "$0")/lib.sh"

name="pip-bt-$(random_suffix)"
body="$(jq -nc --arg loc "$BASTION_LOCATION" --argjson tags "$(bastion_test_tags)" '{
  location: $loc, tags: $tags,
  sku: {name: "Standard"},
  properties: {publicIPAllocationMethod: "Static"}
}')"

expect_denied "Microsoft.Network/publicIPAddresses" "$name" "2024-05-01" "$body" "denied-resource-types"
