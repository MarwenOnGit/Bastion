#!/usr/bin/env bash
# control: nic_no_public_ip
# reference: nic-no-public-ip
# Non-compliant: a NIC whose IP configuration references a public IP.
# Free: the subnet and public IP IDs do not exist. Azure Policy is evaluated by ARM
# before the network provider checks references, so a working Deny answers
# RequestDisallowedByPolicy. Without Deny the provider rejects the missing
# references (InvalidResourceReference), the test fails, and nothing is created.
BASTION_TEST_NAME="nic-public-ip"
# shellcheck source=tests/policy/lib.sh
source "$(dirname "$0")/lib.sh"

sub="$(subscription_id)"
base="/subscriptions/${sub}/resourceGroups/${BASTION_TEST_RG}/providers/Microsoft.Network"
name="nic-bt-$(random_suffix)"
body="$(jq -nc --arg loc "$BASTION_LOCATION" --arg base "$base" --argjson tags "$(bastion_test_tags)" '{
  location: $loc, tags: $tags,
  properties: {
    ipConfigurations: [{
      name: "ipconfig1",
      properties: {
        privateIPAllocationMethod: "Dynamic",
        subnet: {id: ($base + "/virtualNetworks/vnet-does-not-exist/subnets/snet")},
        publicIPAddress: {id: ($base + "/publicIPAddresses/pip-does-not-exist")}
      }
    }]
  }
}')"

expect_denied "Microsoft.Network/networkInterfaces" "$name" "2024-05-01" "$body" "nic-no-public-ip"
