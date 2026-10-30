#!/usr/bin/env bash
# Build this fork's release from the committed checkout.
#
#   svt/build.sh [--keep-patched]
#
# It applies GE's patch script (patches/protonprep-valve-staging.sh, which
# also applies the patches committed here), builds with the Steam Runtime SDK
# container (make redist), and puts the checkout back as it was: the patch
# script rewrites tracked files in the source tree, and none of that is
# meant to be committed. --keep-patched leaves the patched tree, to look at
# why a patch did not apply.
#
# The result is in svt/out/build (SVT_BUILD_DIRECTORY): <tool name>.tar.gz
# and <tool name>.sha512sum, the files GE-Proton publishes for a release.
# The first build takes hours; the next ones reuse what has not changed.
set -eu
set -o pipefail

# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

keep_patched=0
while [ "${#}" -gt 0 ]; do
    case "${1}" in
        --keep-patched) keep_patched=1 ;;
        -h | --help)
            awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next }
                NR > 1 { exit }' "${BASH_SOURCE[0]}"
            exit 0
            ;;
        *) die "unknown argument ${1}" ;;
    esac
    shift
done

# GE's patch script downloads wine-mono with wget; use curl when there is
# no wget (it leaves an archive that is already there alone).
fetch_wine_mono_without_wget() {
    local mono_version archive
    local release_url="https://github.com/wine-mono/wine-mono/releases"
    # shellcheck source=/dev/null
    mono_version="$(. "${repository_root}/patches/wine-mono/source.conf" &&
        printf '%s' "${WINEMONO_VER}")"
    archive="${repository_root}/contrib/wine-mono-${mono_version}-src.tar.xz"
    if command -v wget > /dev/null || [ -f "${archive}" ]; then
        return 0
    fi
    echo "No wget: fetching wine-mono ${mono_version} with curl"
    mkdir -p "${repository_root}/contrib"
    curl -fsSL -o "${archive}.part" \
        "${release_url}/download/wine-mono-${mono_version}/${archive##*/}"
    mv -- "${archive}.part" "${archive}"
}

cd "${repository_root}"
require_clean_checkout
base_tag="$(find_base_tag)" ||
    die "no GE-Proton release tag here; fetch them: git fetch upstream --tags"
tool_name="$(tool_name_for_tag "${base_tag}")"
patch_log="${build_directory}/patchlog.txt"

echo "Building ${tool_name}: ${base_tag} + $(git rev-parse --short HEAD)"
git submodule update --init --recursive --jobs 8
mkdir -p "${build_directory}"

untracked_before="$(mktemp)"
list_untracked_files > "${untracked_before}"
if [ "${keep_patched}" -eq 0 ]; then
    # shellcheck disable=SC2064
    trap "restore_checkout '${untracked_before}'; \
rm -f -- '${untracked_before}'" EXIT
fi

fetch_wine_mono_without_wget
echo "Applying GE's patches (log: ${patch_log})"
if ! ./patches/protonprep-valve-staging.sh > "${patch_log}" 2>&1; then
    die "the patch script failed; see ${patch_log}"
fi
# The patch script carries on after a patch that does not apply, and exits 0.
if grep -E -q "FAILED|Reversed \(or previously applied|can.t find file" \
    "${patch_log}"; then
    die "a patch did not apply; see ${patch_log}"
fi

cd "${build_directory}"
"${repository_root}/configure.sh" --build-name="${tool_name}" \
    --container-engine="${container_engine}"
make -j"$(nproc)" redist

[ -f "${tool_name}.tar.gz" ] || die "the build made no ${tool_name}.tar.gz"
git -C "${repository_root}" rev-parse HEAD > "${build_directory}/built-from"
echo "Built: ${build_directory}/${tool_name}.tar.gz"
echo "Next: svt/release.sh"
