#!/bin/bash
# Execute the shipped class on Java 8, using minimal non-native Steam ID fixtures.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export STS_TEST_JAVAC="${STS_TEST_JAVAC:-/opt/homebrew/opt/openjdk@17/bin/javac}"
export STS_TEST_JAVA="${STS_TEST_JAVA:-$ROOT/payload/jre/$(uname -m)/bin/java}"
python3 "$ROOT/tests/test-mts-finder.py"
