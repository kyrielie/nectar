#!/bin/bash
# Fails if a package test target is missing from Nectar-CI.xctestplan.
# A package's .testTarget only runs in CI when the plan lists it (see
# docs/module-layout.md, "Test plans").
set -euo pipefail
cd "$(dirname "$0")/.."
missing=0
for manifest in Modules/*/Package.swift; do
  dir=$(dirname "$manifest")
  # Matches .testTarget(name: "XTests" ...) in one-line and multi-line manifests.
  for name in $(tr -d '\n\t ' < "$manifest" | grep -oE '\.testTarget\(name:"[A-Za-z0-9_]+"' | sed -E 's/.*name:"([^"]+)"/\1/'); do
    if ! grep -q "\"name\" : \"$name\"" Nectar-CI.xctestplan; then
      echo "Missing from Nectar-CI.xctestplan: $name ($dir)"
      missing=1
    fi
  done
done
exit $missing
