# shellcheck shell=bash
# shellcheck disable=SC2034  # the variables are used by the scripts that
#                              source this file
# Settings and helpers shared by the scripts in this directory. Sourced, not
# run.
#
# These scripts build and publish this fork's releases: a GE-Proton release
# plus the patches committed on the release branch. They are for the fork
# only; nothing here is meant for upstream.

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
github_repository="${SVT_GITHUB_REPOSITORY:-sevaht/SVT-proton-ge-custom}"
release_branch="${SVT_RELEASE_BRANCH:-svt-ge11}"
container_engine="${SVT_CONTAINER_ENGINE:-docker}"
build_directory="${SVT_BUILD_DIRECTORY:-${repository_root}/svt/out/build}"

die() {
    echo "${0##*/}: ${*}" >&2
    exit 1
}

# The GE-Proton release this checkout is built on, e.g. GE-Proton11-11.
find_base_tag() {
    git -C "${repository_root}" describe --tags --abbrev=0 \
        --match 'GE-Proton*'
}

# The name Steam lists the tool under, and the folder it unpacks to. It
# follows the series (GE-Proton11-3 and GE-Proton11-11 are both
# SVT-Proton-GE11), so the tool a game is set to in Steam keeps working from
# one release to the next.
tool_name_for_tag() {
    local base_tag="${1}"
    local series="${base_tag#GE-Proton}"
    echo "SVT-Proton-GE${series%%-*}"
}

# Fails unless the checkout is exactly its last commit. The contents of a
# submodule are not looked at: the patch script rewrites them, and resets
# them itself the next time it runs.
require_clean_checkout() {
    local changes
    changes="$(git -C "${repository_root}" status --porcelain \
        --ignore-submodules=dirty)"
    if [ -n "${changes}" ]; then
        die "uncommitted changes (commit or stash them first):
${changes}"
    fi
}

# The files not tracked by git and not ignored, one per line, sorted.
list_untracked_files() {
    git -C "${repository_root}" ls-files --others --exclude-standard |
        sort
}

# Put the checkout back as it was when the list of untracked files in
# ${1} was made, after the patch script (which rewrites tracked files in
# this tree, and leaves .orig files and new files behind) and the build.
# The checkout was clean then, so everything now different is the build's.
restore_checkout() {
    local untracked_before="${1}"
    local created_file
    git -C "${repository_root}" reset --hard --quiet
    list_untracked_files | comm -13 "${untracked_before}" - |
        while IFS= read -r created_file; do
            rm -f -- "${repository_root}/${created_file}"
        done
    git -C "${repository_root}" submodule foreach --quiet --recursive \
        'git reset --hard --quiet && git clean -f -d -q'
}
