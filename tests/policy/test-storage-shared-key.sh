#!/usr/bin/env bash
# control: storage_shared_key
# reference: storage-shared-key
# Fenrir: P-12 (listKeys). Non-compliant: allowSharedKeyAccess = true. Everything else compliant.
# Cost if it wrongly succeeds: an empty Standard_LRS account for a few seconds (no charge in practice).
BASTION_TEST_NAME="storage-shared-key"
# shellcheck source=tests/policy/lib.sh
source "$(dirname "$0")/lib.sh"

name="stbtsk$(random_suffix)"
body="$(jq -nc --arg loc "$BASTION_LOCATION" --argjson tags "$(bastion_test_tags)" '{
  location: $loc, kind: "StorageV2", sku: {name: "Standard_LRS"}, tags: $tags,
  properties: {
    allowSharedKeyAccess: true,
    publicNetworkAccess: "Disabled",
    minimumTlsVersion: "TLS1_2",
    allowBlobPublicAccess: false,
    supportsHttpsTrafficOnly: true
  }
}')"

expect_denied "Microsoft.Storage/storageAccounts" "$name" "2023-05-01" "$body" "storage-shared-key"
