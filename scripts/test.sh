#!/usr/bin/env bash
set -euo pipefail

# Run tests using temporary scratch path to avoid iCloud Drive FileProvider detritus/code-signing issues
swift test --scratch-path /tmp/machealthos-build "$@"
