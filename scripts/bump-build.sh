#!/bin/sh
# Before each TestFlight upload: build N+1, version MAJOR.MINOR.(N+1) (build N is MAJOR.MINOR.N).
set -eu
cd "$(dirname "$0")/.."
P="Cats&Dogs.xcodeproj/project.pbxproj"
build=$(sed -n 's/.*CURRENT_PROJECT_VERSION = \([0-9]*\);/\1/p' "$P" | sort -n | tail -1)
majorminor=$(sed -n 's/.*MARKETING_VERSION = \([0-9]*\.[0-9]*\).*;/\1/p' "$P" | head -1)
next=$((build + 1))
sed -i '' "s/CURRENT_PROJECT_VERSION = [0-9]*;/CURRENT_PROJECT_VERSION = $next;/; s/MARKETING_VERSION = [0-9.]*;/MARKETING_VERSION = $majorminor.$next;/" "$P"
echo "Build $next, version $majorminor.$next"
