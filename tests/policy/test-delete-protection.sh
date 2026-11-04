#!/usr/bin/env bash
# control: delete_protection
# reference: delete-protection
# DenyAction: deleting a resource tagged bastion-protected=true must be refused.
# Uses a permanent canary, the free user-assigned identity id-bastion-canary in
# bastion-test-rg. It has no bastion-test tag, so cleanup.sh leaves it alone.
# Teardown: delete it by hand after the governance stack is destroyed (docs/COST.md).
BASTION_TEST_NAME="delete-protection"
# shellcheck source=tests/policy/lib.sh
source "$(dirname "$0")/lib.sh"

body="$(jq -nc --arg loc "$BASTION_LOCATION" '{
  location: $loc,
  tags: {owner: "bastion-policy-tests", env: "test", project: "bastion", "bastion-protected": "true"}
}')"

expect_delete_denied "Microsoft.ManagedIdentity/userAssignedIdentities" "id-bastion-canary" "2023-01-31" "$body" "delete-protection"
