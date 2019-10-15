#!/bin/bash

set -eu

# kill ganache on exit
trap 'kill $(jobs -p)' EXIT

yarn run ganache > ganache.log &

OUTPUT="$(yarn run deploy-numeraierasure ganache)"

echo -e "$OUTPUT"

# exit error if failure found in output
if echo $OUTPUT | grep -q 'failure'; then
  exit 1
fi
