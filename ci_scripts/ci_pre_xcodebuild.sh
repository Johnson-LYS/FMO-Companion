#!/bin/sh

set -eu

if [ "${CI_XCODE_CLOUD:-}" != "TRUE" ]; then
    echo "Not running in Xcode Cloud; keeping the project build number."
    exit 0
fi

case "${CI_BUILD_NUMBER:-}" in
    ''|*[!0-9]*)
        echo "CI_BUILD_NUMBER must be a positive integer." >&2
        exit 1
        ;;
esac

if [ "$CI_BUILD_NUMBER" -lt 1 ]; then
    echo "CI_BUILD_NUMBER must be greater than zero." >&2
    exit 1
fi

repository_path="${CI_PRIMARY_REPOSITORY_PATH:-}"
if [ -z "$repository_path" ] || [ ! -d "$repository_path/FMOc.xcodeproj" ]; then
    echo "CI_PRIMARY_REPOSITORY_PATH does not contain FMOc.xcodeproj." >&2
    exit 1
fi

cd "$repository_path"
/usr/bin/xcrun agvtool new-version -all "$CI_BUILD_NUMBER"

for target in FMOc FMOcLiveActivity; do
    for configuration in Debug Release; do
        resolved_version=$(
            /usr/bin/xcrun xcodebuild \
                -project FMOc.xcodeproj \
                -target "$target" \
                -configuration "$configuration" \
                -showBuildSettings \
                | /usr/bin/awk '/^[[:space:]]*CURRENT_PROJECT_VERSION = / { print $3; exit }'
        )

        if [ "$resolved_version" != "$CI_BUILD_NUMBER" ]; then
            echo "Resolved $target $configuration build number '$resolved_version' does not match Xcode Cloud build '$CI_BUILD_NUMBER'." >&2
            exit 1
        fi
    done
done

echo "Bundle build number synchronized with Xcode Cloud build $CI_BUILD_NUMBER before $CI_XCODEBUILD_ACTION."
