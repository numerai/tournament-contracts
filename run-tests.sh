#!/bin/bash

set -eu

# kill ganache on exit
trap 'kill $(jobs -p)' EXIT

yarn run ganache > ganache.log &

yarn run test
