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
# Source is the Flutter China mirror: reachable from both domestic build
# machines (fast) and overseas (slower but works), unlike pub.dev which is
# unreliable from inside China. CI must invoke deps through this script so the
# lock's url: fields don't drift.
set -euo pipefail

# Canonical package source. CI and all contributors must resolve through this.
export PUB_HOSTED_URL="https://pub.flutter-io.cn"

cmd="${1:-get}"
case "$cmd" in
  get)     exec flutter pub get ;;
  upgrade) exec flutter pub upgrade "${@:2}" ;;
  *)       exec flutter pub "$@" ;;
esac
