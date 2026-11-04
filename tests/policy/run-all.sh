#!/usr/bin/env bash
# Run the Bastion policy tests.
#
# A test runs only when its control is Deny (or DenyAction) in policies/effects.json,
# because an Audit policy blocks nothing and the test would (correctly) fail.
#
#   tests/policy/run-all.sh                    run every test whose control is enforced
#   tests/policy/run-all.sh --force <control>  run one test whatever the effect
#                                              (the "red" half of the demo)
#   tests/policy/run-all.sh --list             show each test, its control and effect
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
effects="$root/policies/effects.json"

control_of() { sed -n 's/^# control: //p' "$1" | head -n1; }
effect_of() { jq -r --arg c "$1" '.[$c] // "missing"' "$effects"; }

mode="deny-only"
force_control=""
case "${1:-}" in
  --list) mode="list" ;;
  --force)
    mode="force"
    force_control="${2:?--force needs a control name}"
    ;;
  "") ;;
  *)
    echo "usage: $0 [--list | --force <control>]" >&2
    exit 2
    ;;
esac

summary="${GITHUB_STEP_SUMMARY:-/dev/null}"
{
  echo "## Bastion policy tests"
  echo
  echo "| Test | Control | Effect | Result |"
  echo "|---|---|---|---|"
} >>"$summary"

pass=0 fail=0 skip=0
for t in "$here"/test-*.sh; do
  name="$(basename "$t" .sh)"
  control="$(control_of "$t")"
  effect="$(effect_of "$control")"

  if [[ "$mode" == "list" ]]; then
    printf '%-32s %-28s %s\n' "$name" "$control" "$effect"
    continue
  fi

  run=false
  if [[ "$mode" == "force" ]]; then
    [[ "$control" == "$force_control" ]] && run=true
  elif [[ "$effect" == "Deny" || "$effect" == "DenyAction" ]]; then
    run=true
  fi

  if [[ "$run" != true ]]; then
    skip=$((skip + 1))
    echo "| $name | $control | $effect | skipped (not enforced) |" >>"$summary"
    continue
  fi

  if bash "$t"; then
    pass=$((pass + 1))
    echo "| $name | $control | $effect | PASS |" >>"$summary"
  else
    fail=$((fail + 1))
    echo "| $name | $control | $effect | **FAIL** |" >>"$summary"
  fi
done

[[ "$mode" == "list" ]] && exit 0

echo "passed=$pass failed=$fail skipped=$skip"
{
  echo
  echo "passed=$pass failed=$fail skipped=$skip"
} >>"$summary"

if [[ "$mode" == "force" && $((pass + fail)) -eq 0 ]]; then
  echo "no test found for control '$force_control'" >&2
  exit 2
fi
[[ $fail -eq 0 ]]
