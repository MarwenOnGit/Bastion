#!/usr/bin/env bash
# Delete every resource tagged bastion-test=true in bastion-test-rg.
# Refuses any other resource group, and only ever deletes tagged resources.
#
#   tests/policy/cleanup.sh [resource-group]   (default and only accepted value: bastion-test-rg)
set -euo pipefail

BASTION_TEST_NAME="cleanup"
# shellcheck source=tests/policy/lib.sh
source "$(dirname "$0")/lib.sh"
trap - EXIT

rg="${1:-$BASTION_TEST_RG}"
require_test_rg "$rg"

mapfile -t ids < <(az resource list --resource-group "$rg" --tag bastion-test=true --query "[].id" -o tsv)

if [[ ${#ids[@]} -eq 0 ]]; then
  log "nothing to clean in $rg"
  exit 0
fi

failed=0
for id in "${ids[@]}"; do
  # Belt and braces: the ID itself must be inside the test group.
  if [[ "${id,,}" != *"/resourcegroups/${BASTION_TEST_RG}/"* ]]; then
    log "skipping $id: not in $BASTION_TEST_RG"
    continue
  fi
  log "deleting $id"
  if ! az resource delete --ids "$id" --only-show-errors; then
    log "could not delete $id"
    failed=1
  fi
done

exit "$failed"
