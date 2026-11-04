#!/usr/bin/env bash
# control: keyvault_rbac
# reference: keyvault-rbac
# Non-compliant: enableRbacAuthorization = false (vault access policies).
# If it wrongly succeeds, the trap deletes it; it stays soft-deleted (no charge).
BASTION_TEST_NAME="keyvault-rbac"
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
    enablePurgeProtection: true,
    enableRbacAuthorization: false,
    accessPolicies: []
  }
}')"

expect_denied "Microsoft.KeyVault/vaults" "$name" "2023-07-01" "$body" "keyvault-rbac"
