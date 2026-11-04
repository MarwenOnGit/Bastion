#!/usr/bin/env bash
# control: mgmt_ports_internet
# reference: mgmt-ports-internet
# Non-compliant: an NSG (free) with an inline rule allowing SSH (22) from any source.
BASTION_TEST_NAME="mgmt-ports-internet"
# shellcheck source=tests/policy/lib.sh
source "$(dirname "$0")/lib.sh"

name="nsg-bt-ssh-$(random_suffix)"
body="$(jq -nc --arg loc "$BASTION_LOCATION" --argjson tags "$(bastion_test_tags)" '{
  location: $loc, tags: $tags,
  properties: {
    securityRules: [{
      name: "allow-ssh-from-internet",
      properties: {
        priority: 100, direction: "Inbound", access: "Allow", protocol: "Tcp",
        sourceAddressPrefix: "*", sourcePortRange: "*",
        destinationAddressPrefix: "*", destinationPortRange: "22"
      }
    }]
  }
}')"

expect_denied "Microsoft.Network/networkSecurityGroups" "$name" "2024-05-01" "$body" "mgmt-ports-internet"
