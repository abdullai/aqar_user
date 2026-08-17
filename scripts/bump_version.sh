#!/usr/bin/env bash
# Usage (from repo root): ./scripts/bump_version.sh [--patch|--minor|--major] [--dry-run]
set -euo pipefail
cd "$(dirname "$0")/.."
dart run tool/bump_version.dart "$@"
