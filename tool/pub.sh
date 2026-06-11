#!/usr/bin/env bash
# Wrapper around `flutter pub get/upgrade` that pins the package source so
# pubspec.lock's `url:` fields stay stable across machines.
#
# Why this exists: pubspec.lock records the download URL of every package, and
# that URL comes from $PUB_HOSTED_URL at resolve time. When team members run
# `flutter pub get` with different mirrors configured (pub.dev vs
# pub.flutter-io.cn vs a university mirror), the lock file churns on every
# commit. This script forces the canonical source for everyone and CI.
#
# Usage:
#   tool/pub.sh get        # equivalent to `flutter pub get`   (default)
#   tool/pub.sh upgrade    # equivalent to `flutter pub upgrade`
#
# To use a local mirror only for download SPEED without rewriting the lock,
# DON'T set PUB_HOSTED_URL globally — this script intentionally overrides it.
set -euo pipefail

# Canonical package source. Keep in sync with the team convention in README.
export PUB_HOSTED_URL="https://pub.dev"

cmd="${1:-get}"
case "$cmd" in
  get)     exec flutter pub get ;;
  upgrade) exec flutter pub upgrade "${@:2}" ;;
  *)       exec flutter pub "$@" ;;
esac
