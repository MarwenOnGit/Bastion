#!/usr/bin/env bash
# control: keyvault_purge_protection
# reference: keyvault-purge-protection
# Non-compliant: enablePurgeProtection not set. RBAC and private access are set so only
# this control can deny. If it wrongly succeeds, the trap deletes it (no charge).
BASTION_TEST_NAME="keyvault-purge-protection"
# shellcheck source=tests/policy/lib.sh
source "$(dirname "$0")/lib.sh"

name="kvbt$(random_suffix)"
body="$(jq -nc --arg loc "$BASTION_LOCATION" --arg tid "$(tenant_id)" --argjson tags "$(bastion_test_tags)" '{
  location: $loc, tags: $tags,
  properties: {
    tenantId: $tid,
    sku: {family: "A", name: "standard"},
    enableSoftDelete: true,
    softDeleteRetentionInDays: 7,
    publicNetworkAccess: "Disabled",
    enableRbacAuthorization: true
  }
}')"

expect_denied "Microsoft.KeyVault/vaults" "$name" "2023-07-01" "$body" "keyvault-purge-protection"
