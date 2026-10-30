#!/usr/bin/env bash
# Publish the build of svt/build.sh as a GitHub release of this fork.
#
#   svt/release.sh              release svt-GE-Proton11-11
#   svt/release.sh --rev 2      a rebuild of the same GE release (-r2)
#   svt/release.sh --draft      create it as a draft, to look over first;
#                               publish it from its page on GitHub, not by
#                               running this again
#
# The release holds what GE-Proton publishes for each of its own: the archive
# (<tool name>.tar.gz, with one top-level folder named for the tool, so
# unpacking it in compatibilitytools.d is the installation) and its
# <tool name>.sha512sum. Anything that installs GE-Proton from its releases
# can take these the same way. The tag is svt-<GE release>[-r<N>]; GE's own
# tags are never reused.
#
# It must be run from the release branch, clean and pushed, with a build of
# exactly that commit: what is released is what is on GitHub. Needs the
# GitHub CLI (gh), logged in with push access.
set -eu
set -o pipefail

# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

revision=""
draft_flags=()
while [ "${#}" -gt 0 ]; do
    case "${1}" in
        --rev)
            revision="${2:?--rev needs a number}"
            shift
            ;;
        --draft) draft_flags=(--draft) ;;
        -h | --help)
            awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next }
                NR > 1 { exit }' "${BASH_SOURCE[0]}"
            exit 0
            ;;
        *) die "unknown argument ${1}" ;;
    esac
    shift
done
case "${revision}" in
    "" | *[!0-9]*) [ -z "${revision}" ] || die "--rev takes a number" ;;
esac

command -v gh > /dev/null || die "the GitHub CLI (gh) is needed"
cd "${repository_root}"
current_branch="$(git rev-parse --abbrev-ref HEAD)"
[ "${current_branch}" = "${release_branch}" ] ||
    die "on '${current_branch}', not the release branch '${release_branch}'"
require_clean_checkout
git fetch --quiet origin "${release_branch}"
[ "$(git rev-parse HEAD)" = "$(git rev-parse "origin/${release_branch}")" ] ||
    die "this is not what origin/${release_branch} has; push it first"

base_tag="$(find_base_tag)" || die "no GE-Proton release tag here"
tool_name="$(tool_name_for_tag "${base_tag}")"
release_tag="svt-${base_tag}${revision:+-r${revision}}"
archive="${build_directory}/${tool_name}.tar.gz"
checksums="${build_directory}/${tool_name}.sha512sum"
[ -f "${archive}" ] && [ -f "${checksums}" ] ||
    die "no build in ${build_directory}; run svt/build.sh"
[ "$(cat "${build_directory}/built-from" 2> /dev/null)" = \
    "$(git rev-parse HEAD)" ] ||
    die "the build is not of this commit; run svt/build.sh"
(cd "${build_directory}" && sha512sum --check --quiet \
    "${tool_name}.sha512sum") || die "the archive does not match its checksum"
# Listed, not viewed: a draft has no tag yet, so viewing it by tag fails
# and a second release with the same tag would be made.
existing_tags="$(gh release list --repo "${github_repository}" \
    --limit 200 --json tagName --jq '.[].tagName')"
if printf '%s\n' "${existing_tags}" | grep -F -x -q "${release_tag}"; then
    die "release ${release_tag} exists, as a draft or published (a rebuild
needs --rev N; a draft is published from its page on GitHub)"
fi

notes_file="$(mktemp)"
trap 'rm -f -- "${notes_file}"' EXIT
{
    echo "${tool_name}: ${base_tag} with these changes on top of it:"
    echo
    git log --format='- %s' --no-merges --reverse "${base_tag}..HEAD"
    echo
    echo "## Install"
    echo
    echo "Unpack it in Steam's compatibility tools folder and restart Steam:"
    echo
    echo '```'
    echo "mkdir -p ~/.local/share/Steam/compatibilitytools.d"
    echo "tar -xzf ${tool_name}.tar.gz \\"
    echo "    -C ~/.local/share/Steam/compatibilitytools.d"
    echo '```'
    echo
    echo "Then choose **${tool_name}** under the game's Properties >"
    echo "Compatibility. Verify the download with"
    echo "\`sha512sum --check ${tool_name}.sha512sum\`."
} > "${notes_file}"

gh release create "${release_tag}" "${archive}" "${checksums}" \
    --repo "${github_repository}" \
    --target "$(git rev-parse HEAD)" \
    --title "${tool_name} ${base_tag#GE-Proton}${revision:+ (r${revision})}" \
    --notes-file "${notes_file}" \
    "${draft_flags[@]+"${draft_flags[@]}"}"
echo "Released ${release_tag}"
