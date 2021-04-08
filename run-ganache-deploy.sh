#!/bin/bash

set -e

# run ganache in background
yarn run ganache > ganache.log &
PID="$!"
sleep 5

OUTPUT="$(yarn run deploy-numeraierasure ganache 2>&1)"

echo -e "$OUTPUT"

kill $PID

## exit error if failure found in output
if echo "$OUTPUT" | grep 'failure' ; then
  echo "detected failure..."
  exit 1
fi
