#!/bin/bash
#
# Entry point of the test install that `mpdev verify` runs.
#
# Replaces /bin/deploy_with_tests.sh of Google's deployer_helm image. It puts
# the test values from /data-test over the form, then runs the same install as
# a real deploy (deploy.sh) and waits for the app to be ready.

set -euo pipefail

test_schema="/data-test/schema.yaml"
if [[ -f "${test_schema}" ]]; then
  overlay_test_schema.py \
    --test_schema "${test_schema}" \
    --original_schema "/data/schema.yaml" \
    --output "/data/schema.yaml"
fi

DEPLOY_MODE=test exec /bin/deploy.sh
