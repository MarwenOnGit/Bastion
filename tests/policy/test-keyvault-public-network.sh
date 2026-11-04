#!/usr/bin/env bash
# control: keyvault_public_network
# reference: keyvault-public-network
# Non-compliant: publicNetworkAccess = Enabled. Key Vault has no fixed cost.
# If it wrongly succeeds, the trap deletes it; the vault then sits soft-deleted for
# 7 days (no charge). The tester identity cannot purge it (that needs a
# subscription-scope action), which is why every run uses a random name.
BASTION_TEST_NAME="keyvault-public-network"
# shellcheck source=tests/policy/lib.sh
source "$(dirname "$0")/lib.sh"

name="kvbt$(random_suffix)"
body="$(jq -nc --arg loc "$BASTION_LOCATION" --arg tid "$(tenant_id)" --argjson tags "$(bastion_test_tags)" '{
  location: $loc, tags: $tags,
  properties: {
    tenantId: $tid,
    sku: {family: "A", name: "standard"},
    enableRbacAuthorization: true,
    enableSoftDelete: true,
    enablePurgeProtection: true,
    softDeleteRetentionInDays: 7,
    publicNetworkAccess: "Enabled"
  }
}')"

expect_denied "Microsoft.KeyVault/vaults" "$name" "2023-07-01" "$body" "keyvault-public-network"
