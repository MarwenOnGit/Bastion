#!/usr/bin/env bash
# control: storage_blob_public_access
# reference: storage-blob-public-access
# Fenrir: D-01. Non-compliant: allowBlobPublicAccess = true. Everything else compliant.
BASTION_TEST_NAME="storage-blob-public-access"
# shellcheck source=tests/policy/lib.sh
source "$(dirname "$0")/lib.sh"

name="stbtbpa$(random_suffix)"
body="$(jq -nc --arg loc "$BASTION_LOCATION" --argjson tags "$(bastion_test_tags)" '{
  location: $loc, kind: "StorageV2", sku: {name: "Standard_LRS"}, tags: $tags,
  properties: {
    allowSharedKeyAccess: false,
    publicNetworkAccess: "Disabled",
    minimumTlsVersion: "TLS1_2",
    allowBlobPublicAccess: true,
    supportsHttpsTrafficOnly: true
  }
}')"

expect_denied "Microsoft.Storage/storageAccounts" "$name" "2023-05-01" "$body" "storage-blob-public-access"
