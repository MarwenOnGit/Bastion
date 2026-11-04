#!/usr/bin/env bash
# control: storage_secure_transfer
# reference: storage-secure-transfer
# Non-compliant: supportsHttpsTrafficOnly = false. Everything else compliant.
BASTION_TEST_NAME="storage-secure-transfer"
# shellcheck source=tests/policy/lib.sh
source "$(dirname "$0")/lib.sh"

name="stbtst$(random_suffix)"
body="$(jq -nc --arg loc "$BASTION_LOCATION" --argjson tags "$(bastion_test_tags)" '{
  location: $loc, kind: "StorageV2", sku: {name: "Standard_LRS"}, tags: $tags,
  properties: {
    allowSharedKeyAccess: false,
    publicNetworkAccess: "Disabled",
    minimumTlsVersion: "TLS1_2",
    allowBlobPublicAccess: false,
    supportsHttpsTrafficOnly: false
  }
}')"

expect_denied "Microsoft.Storage/storageAccounts" "$name" "2023-05-01" "$body" "storage-secure-transfer"
