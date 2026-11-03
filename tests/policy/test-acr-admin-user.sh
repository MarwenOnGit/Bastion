#!/usr/bin/env bash
# control: acr_admin_user
# reference: acr-admin-user
# Fenrir: P-13 (listCredentials). Non-compliant: adminUserEnabled = true.
# Cost if it wrongly succeeds: Basic registry, about $0.17 a day, deleted by the trap within a minute.
BASTION_TEST_NAME="acr-admin-user"
# shellcheck source=tests/policy/lib.sh
source "$(dirname "$0")/lib.sh"

name="acrbt$(random_suffix)"
body="$(jq -nc --arg loc "$BASTION_LOCATION" --argjson tags "$(bastion_test_tags)" '{
  location: $loc, sku: {name: "Basic"}, tags: $tags,
  properties: {adminUserEnabled: true}
}')"

expect_denied "Microsoft.ContainerRegistry/registries" "$name" "2023-07-01" "$body" "acr-admin-user"
