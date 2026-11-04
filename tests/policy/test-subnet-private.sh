#!/usr/bin/env bash
# control: subnet_private
# reference: subnet-private
# Non-compliant: a VNet whose subnet keeps default outbound access. The subnet names an
# NSG (a reference that does not exist) so that only this control can deny. Without
# Deny, the network provider rejects the missing NSG and nothing is created.
BASTION_TEST_NAME="subnet-private"
# shellcheck source=tests/policy/lib.sh
source "$(dirname "$0")/lib.sh"

sub="$(subscription_id)"
nsg="/subscriptions/${sub}/resourceGroups/${BASTION_TEST_RG}/providers/Microsoft.Network/networkSecurityGroups/nsg-does-not-exist"
name="vnet-bt-priv-$(random_suffix)"
body="$(jq -nc --arg loc "$BASTION_LOCATION" --arg nsg "$nsg" --argjson tags "$(bastion_test_tags)" '{
  location: $loc, tags: $tags,
  properties: {
    addressSpace: {addressPrefixes: ["10.99.0.0/24"]},
    subnets: [{name: "snet-test", properties: {addressPrefix: "10.99.0.0/26", defaultOutboundAccess: true, networkSecurityGroup: {id: $nsg}}}]
  }
}')"

expect_denied "Microsoft.Network/virtualNetworks" "$name" "2024-05-01" "$body" "subnet-private"
