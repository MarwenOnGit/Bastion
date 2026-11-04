#!/usr/bin/env bash
# control: subnet_nsg
# reference: subnet-nsg
# Non-compliant: a VNet (free) whose only subnet has no NSG. Default outbound access is
# off, so only this control can deny.
BASTION_TEST_NAME="subnet-nsg"
# shellcheck source=tests/policy/lib.sh
source "$(dirname "$0")/lib.sh"

name="vnet-bt-nsg-$(random_suffix)"
body="$(jq -nc --arg loc "$BASTION_LOCATION" --argjson tags "$(bastion_test_tags)" '{
  location: $loc, tags: $tags,
  properties: {
    addressSpace: {addressPrefixes: ["10.98.0.0/24"]},
    subnets: [{name: "snet-test", properties: {addressPrefix: "10.98.0.0/26", defaultOutboundAccess: false}}]
  }
}')"

expect_denied "Microsoft.Network/virtualNetworks" "$name" "2024-05-01" "$body" "subnet-nsg"
