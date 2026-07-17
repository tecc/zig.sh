#!/usr/bin/env bash

# This Bash script downloads a specified version of Zig if necessary.
# Afterwards, it invokes the Zig binary with the arguments given to the script.
# Idea based on:
#   https://matklad.github.io/2023/06/02/the-worst-zig-version-manager.html
#
# Options (environment variables)
#   ZIGSH_FORCE_DOWNLOAD
#     Forces a download of Zig regardless of whether it is already downloaded
#     or not.
#   ZIG_VERSION
#     Override the version of Zig used.
#     By default:
#       - If a .zig-version file exists next to the script file, ZIG_VERSION is
#         set to the contents of that file. For example:
#           - A/zig.sh would use A/.zig-version
#           - B/zig.sh would use B/.zig-version
#       - Otherwise, it is set to "master".
#     It is important to note that only those versions that are listed in
#     https://ziglang.org/download/index.json are supported.
#
# Dependencies
#   bash  to run this script
#   curl  to fetch data from the internet
#   jq    to parse JSON objects
# 
# Copyright (c) 2026 tecc
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

set -euo pipefail

# https://stackoverflow.com/a/246128/11009859
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

if [ ! -z ${ZIG_VERSION+x} ]; then
    # ZIG_VERSION is already set, do nothing
    :
elif [ -f "$SCRIPT_DIR/.zig-version" ]; then
    # .zig-version exists, so use that
    ZIG_VERSION=$(cat "$SCRIPT_DIR/.zig-version" | sed 's/^ *//;s/ *$//')
else
    # No version was set explicitly, so default to master
    ZIG_VERSION="master"
fi

ZIG_BASE_DIR="$SCRIPT_DIR/zig"
ZIG_VERSIONED_DIR="$ZIG_BASE_DIR/$ZIG_VERSION"

downloadZig() {
    C_info=""
    C_mark=""
    C_err=""
    C_reset=""

    # Snippet based on: https://unix.stackexchange.com/a/10065
    if test -t 1; then
        ncolors=$(tput colors)
        if test -n "$ncolors" && test $ncolors -ge 8; then
            C_info="$(tput bold)$(tput setaf 7)"
            C_mark="$(tput bold)$(tput setaf 5)"
            C_err="$(tput bold)$(tput setaf 1)"
            C_reset="$(tput sgr0)"
        fi
    fi

    printf "${C_info}zig.sh: preparing to download version ${C_mark}$ZIG_VERSION ${C_info}to ${C_mark}$ZIG_VERSIONED_DIR${C_reset}\n"
    # Find out which build of Zig to download
    case $(uname -s) in
        "Linux")
            operating_system="linux" ;;
        "Darwin")
            operating_system="macos" ;;
        *)
            echo "Unknown operating system; cannot download zig" ;;
    esac
    architecture=$(uname -m)

    if [ -f $ZIG_VERSIONED_DIR ]; then
        rm -rf $ZIG_VERSIONED_DIR
    fi
    mkdir -p $ZIG_BASE_DIR

    printf "${C_info}zig.sh: fetching version index...${C_reset}\n"
    versions=$(curl -L "https://ziglang.org/download/index.json")

    jq_version=".[\"$ZIG_VERSION\"]"
    jq_download="$jq_version.[\"$architecture-$operating_system\"]"

    version=$(echo $versions | jq -r "$jq_version.version")
    date=$(echo $versions | jq -r "$jq_version.date")
    tarball_url=$(echo $versions | jq -r "$jq_download.tarball")
    tarball_shasum=$(echo $versions | jq -r "$jq_download.shasum")
    archive_name=$(basename $tarball_url)

    if [ "$version" == "null" ]; then
        printf "${C_err}zig.sh: requested version ${C_mark}$ZIG_VERSION${C_err} does not exist${C_reset}\n"
        exit 1
    fi
    printf "${C_info}zig.sh: resolved ${C_mark}$ZIG_VERSION${C_info} as version ${C_mark}$version ($date)${C_info}; downloading...${C_reset}\n"

    mkdir -p $ZIG_VERSIONED_DIR

    curl -L --output "$ZIG_BASE_DIR/$archive_name" "$tarball_url"
    echo "$tarball_shasum $ZIG_BASE_DIR/$archive_name" | sha256sum --check

    printf "${C_info}zig.sh: extracting...${C_reset}\n"
    tar -xf "$ZIG_BASE_DIR/$archive_name" -C "$ZIG_VERSIONED_DIR" --strip-components=1
    rm "$ZIG_BASE_DIR/$archive_name"

    printf "${C_info}zig.sh: done! enjoy programming in Zig ${C_mark}<3${C_info}\n"
}


# If zig exists, don't download it.
# Allow overriding.
if [ ! -f "$ZIG_VERSIONED_DIR/zig" ] || [ ! -z ${ZIGSH_FORCE_DOWNLOAD+x} ]; then
    downloadZig
fi

"$ZIG_VERSIONED_DIR/zig" $@
