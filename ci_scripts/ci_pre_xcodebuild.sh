#!/bin/sh

set -eu

script_directory=$(cd "$(dirname "$0")" && pwd)
script_repository_path=$(cd "$script_directory/.." && pwd)

if [ "${CI_XCODE_CLOUD:-}" = "TRUE" ]; then
    case "${CI_XCODEBUILD_ACTION:-}" in
        test-without-building)
            echo "Skipping source validation and build-number synchronization for test-without-building; this action reuses previously built artifacts."
            exit 0
            ;;
        analyze|archive|build|build-for-testing)
            ;;
        '')
            echo "CI_XCODEBUILD_ACTION is required in Xcode Cloud." >&2
            exit 1
            ;;
        *)
            echo "Unsupported CI_XCODEBUILD_ACTION: $CI_XCODEBUILD_ACTION" >&2
            exit 1
            ;;
    esac
fi

repository_path="${CI_PRIMARY_REPOSITORY_PATH:-$script_repository_path}"
if [ ! -d "$repository_path/FMOc.xcodeproj" ] && [ -d "$script_repository_path/FMOc.xcodeproj" ]; then
    repository_path="$script_repository_path"
fi

if [ "${CI_XCODE_CLOUD:-}" = "TRUE" ] && [ ! -d "$repository_path/FMOc.xcodeproj" ]; then
    echo "The $CI_XCODEBUILD_ACTION action requires source, but FMOc.xcodeproj is unavailable in the restored Xcode Cloud environment." >&2
    exit 1
fi

python3 "$script_directory/validate_localizations.py"

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
