#!/usr/bin/env bash
# control: denied_resource_types
# reference: denied-resource-types
# Non-compliant: a public IP address and a container group, two of the denied types.
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

# Case 1: a paid or internet-facing type.
rc=0
expect_denied "Microsoft.Network/publicIPAddresses" "$name" "2024-05-01" "$body" "denied-resource-types" || rc=1

# Case 2: compute that could carry id-bastion-policy and run code as it (review
# finding 1). A small Linux container group with no public IP and no identity.
# Cost if it wrongly succeeds: a few cents an hour, deleted by the trap.
cg="cg-bt-$(random_suffix)"
cg_body="$(jq -nc --arg loc "$BASTION_LOCATION" --argjson tags "$(bastion_test_tags)" '{
  location: $loc, tags: $tags,
  properties: {
    osType: "Linux",
    restartPolicy: "Never",
    containers: [{
      name: "hello",
      properties: {
        image: "mcr.microsoft.com/azuredocs/aci-helloworld:latest",
        resources: {requests: {cpu: 1, memoryInGB: 1}}
      }
    }]
  }
}')"
expect_denied "Microsoft.ContainerInstance/containerGroups" "$cg" "2023-05-01" "$cg_body" "denied-resource-types" || rc=1

exit "$rc"
