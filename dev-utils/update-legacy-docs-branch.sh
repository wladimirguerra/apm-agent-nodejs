#!/bin/bash
#
# Create a PR to update the `do-not-delete_legacy-docs` branch to match the
# state of "main" for the just-tagged release. The `do-not-delete_legacy-docs`
# branch needs to be updated for the current docs build.
#
# (Here "legacy docs" means the old Elastic (v1?) docs system based on
# AsciiDoc sources and the elastic/docs.git tooling. Around Mar/Apr 2025
# this docs system is being phased out in favour of a "docs v3" system based
# on Markdown sources and new tooling.)
#
# Usage:
#   ./dev-utils/update-legacy-docs-branch.sh [TARGTAG [LASTTAG]]

if [ "$TRACE" != "" ]; then
    export PS4='${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
set -o errexit
set -o pipefail

function fatal {
    echo "$(basename $0): error: $*"
    exit 1
}

TOP=$(cd $(dirname $0)/../ >/dev/null; pwd)
WRKDIR=${TOP}/build/update-legacy-docs-branch

echo "# Creating working git clone in: ${WRKDIR}/apm-agent-nodejs"
rm -rf $WRKDIR
mkdir -p $WRKDIR
cd $WRKDIR
git clone git@github.com:elastic/apm-agent-nodejs.git
cd apm-agent-nodejs

# Allow passing in target tag (first arg), in case the latest commit is no
# longer the tagged release commit.
TARGTAG="$1"
if [[ -z "$TARGTAG" ]]; then
    TARGTAG=$(git tag --points-at HEAD)
fi
if [[ ! ("$TARGTAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]$) ]]; then
    fatal "the target tag, '${TARGTAG}', does not look like a release tag"
fi
# echo "TARGTAG=$TARGTAG"

# Allow passing in last tag (second arg), in case the
# 'do-not-delete_legacy-docs' branch wasn't updated for some previous releases.
LASTTAG="$2"
if [[ -z "$LASTTAG" ]]; then
    readonly NUM_COMMITS_SANITY_GUARD=200
    LASTTAG=$(
        git log --pretty=format:%h -$NUM_COMMITS_SANITY_GUARD | tail -n +2 | while read sha; do
            possible=$(git tag --points-at $sha)
            if [[ "$possible" =~ ^v[0-9]+\.[0-9]+\.[0-9]$ ]]; then
                echo $possible
                break
            fi
        done
    )
    if [[ -z "$LASTTAG" ]]; then
        fatal "could not find previous release tag in last $NUM_COMMITS_SANITY_GUARD commits"
    fi
fi
if [[ ! ("$LASTTAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]$) ]]; then
    fatal "the last tag, '${LASTTAG}', does not look like a release tag"
fi
# echo "LASTTAG=$LASTTAG"


# Merging generally fails, IME. Let's attempt to cherry-pick each commit.
# - That 'awk' command is to reverse the lines of commit shas.
#   `tac` works on Linux, `tail -r` works on BSD/macOS.
#   https://stackoverflow.com/a/744093/14444044
echo
echo "# Creating PR to update 'do-not-delete_legacy-docs' branch with commits from $LASTTAG to $TARGTAG."
FEATBRANCH=update-legacy-docs-branch-$(date +%Y%m%d)
git checkout do-not-delete_legacy-docs
git checkout -b "$FEATBRANCH"
git log --pretty=format:"%h" $LASTTAG...$TARGTAG \
    | awk '{a[i++]=$0} END {for (j=i-1; j>=0;) print a[j--] }' \
    | while read sha; do
        echo "$ git cherry-pick $sha"
        git cherry-pick $sha
    done

RELEASE_PR=$(git log --pretty=format:"%s" -1 $TARGTAG | sed -E 's/^.* \(\#([0-9]+)\)$/\1/')
echo
echo "# You can create a PR now with:"
echo "    cd $WRKDIR/apm-agent-nodejs"
echo "    gh pr create -w -B "do-not-delete_legacy-docs" -t 'docs: update "do-not-delete_legacy-docs" branch for $TARGTAG release' --body 'Refs: #$RELEASE_PR (release PR)'"

