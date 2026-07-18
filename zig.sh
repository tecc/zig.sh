#!/usr/bin/env bash

# zig.sh by tecc - https://github.com/tecc/zig.sh
# 
# This Bash script downloads a specified version of Zig if necessary.
# It then invokes the Zig binary with the arguments given to the script.
# Idea based on:
#   https://matklad.github.io/2023/06/02/the-worst-zig-version-manager.html
#
# Options (environment variables)
#   ZIGSH_FORCE_DOWNLOAD
#     Forces a download of Zig regardless of whether it is already downloaded
#     or not.
#   ZIGSH_VERBOSE
#     Output more stuff. Useful for debugging.
#   ZIGSH_PROJECT_DIR
#     Set the project directory for which Zig installations will be made.
#     By default, this takes the value of the directory the script file is in.
#   ZIGSH_ONLY_INSTALL
#     Do not run Zig after having installed the tools.
#   ZIGSH_NO_ZLS
#     Do not install ZLS.
#     By default this option is 0, meaning that ZLS is installed.
#     The ZLS version is based on the ZIG_VERSION.
#   ZIG_VERSION
#     Override the version of Zig used.
#     By default:
#       - If a .zig-version file exists in ZIGSH_PROJECT_DIR, ZIG_VERSION is
#         set to the contents of that file. For example:
#           - A/zig.sh would use A/.zig-version
#           - B/zig.sh would use B/.zig-version
#       - If a build.zig.zon file exists in ZIGSH_PROJECT_DIR, and it contains
#         a .minimum_zig_version field, ZIG_VERSION is set to the value of that
#         field.
# 
# Dependencies
#   bash      to run this script
#   curl      to fetch data from the internet
#   minisign  to verify file signatures
#   sed       to find substrings in files
#   tar       to extract archives
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

# Formatting parameters for colours
C_norm=""
C_info=""
C_mark=""
C_err=""
C_reset=""

# Snippet based on: https://unix.stackexchange.com/a/10065
if test -t 1; then
    ncolors=$(tput colors)
    if test -n "$ncolors" && test $ncolors -ge 8; then
        C_norm="$(tput sgr0)$(tput setaf 7)"
        C_dbg="$(tput sitm)$(tput dim)"
        C_info="$(tput bold)$(tput setaf 6)"
        C_mark="$(tput bold)$(tput setaf 5)"
        C_err="$(tput bold)$(tput setaf 1)"
        C_reset="$(tput sgr0)"
    fi
fi

logWrite() {
    printf "$@" >&2
}
logError() {
    logWrite "${C_err}zig.sh! ${C_norm}%s${C_reset}\n" "$*"
}
logInfo() {
    logWrite "${C_info}zig.sh: ${C_norm}%s${C_reset}\n" "$*"
}
logDebug() {
    if [ $ZIGSH_VERBOSE == 1 ]; then
        logWrite "${C_dbg}zig.sh: %s${C_reset}\n" "$*"
    fi
}

ZIGSH_VERBOSE=${ZIGSH_VERBOSE:=0}

if [ $ZIGSH_VERBOSE ]; then
    exec 3>&2
else
    exec 3>/dev/null
fi

# By default, ZIGSH_PROJECT_DIR is whatever directory zig.sh is in.
# https://stackoverflow.com/a/246128/11009859
ZIGSH_PROJECT_DIR=${ZIGSH_PROJECT_DIR:=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )}

# ZIG_VERSION detection
ZIG_VERSION=${ZIG_VERSION:=}
if [ -z "$ZIG_VERSION" ] && [ -f "$ZIGSH_PROJECT_DIR/.zig-version" ]; then
    # .zig-version exists, so use that
    ZIG_VERSION=$(cat "$ZIGSH_PROJECT_DIR/.zig-version" | sed 's/^ *//;s/ *$//')
fi
if [ -z "$ZIG_VERSION" ] && [ -f "$ZIGSH_PROJECT_DIR/build.zig.zon" ]; then
    bzz_min_version=$(cat "$ZIGSH_PROJECT_DIR/build.zig.zon" | sed -n "s/^.*minimum_zig_version\s*=\s*\"\(.*\)\".*$/\1/p")
    # bzz_min_version is empty if build.zig.zon does not contain a minimum_zig_version
    if [ -n $bzz_min_version ]; then
        ZIG_VERSION=$bzz_min_version
    fi
fi
if [ -z "$ZIG_VERSION" ]; then
    # No version detected, so error
    logError "no version detected; use either ${C_mark}ZIG_VERSION${C_norm} or ${C_mark}.zig-version${C_norm} to configure"
    exit 1
fi

ZIG_BASE_DIR="$ZIGSH_PROJECT_DIR/zig"
ZIG_MINISIGN_PUBKEY="RWSGOq2NVecA2UPNdBUZykf1CCb147pkmdtYxgb3Ti+JO/wCYvhbAb/U"

# Determine which platform we're on
if [ -z ${ZIGSH_PLATFORM+x} ]; then
    # Get platform parameters
    case $(uname -s) in
        "Linux")
            operating_system="linux" ;;
        "Darwin")
            operating_system="macos" ;;
        *)
            logError "Unknown operating system; cannot select Zig build" ;;
    esac
    architecture=$(uname -m)
    ZIGSH_PLATFORM="$architecture-$operating_system"
fi

ZIG_VERSIONED_DIR="$ZIG_BASE_DIR/$ZIGSH_PLATFORM-$ZIG_VERSION"

last_successful_mirror=0
mirroredFetch() {
    path=""
    output_file=""
    output_var=""
    
    OPTIND=1
    while getopts "p:o:v:" opt ; do
        case $opt in
            p)
                path=$OPTARG
                ;;
            o)
                output_file=$OPTARG
                ;;
            v)
                output_var=$OPTARG
                ;;
            *)
                logError "internal error: bad argument"
                exit 1
                ;;
        esac
    done

    curl_args=("--output" "$output_file")
    
    success=0
    mirror_count=${#ZIGSH_MIRRORS[@]}
    for mirror_index_base in ${!ZIGSH_MIRRORS[@]};
    do
        mirror_index=$(( ($mirror_index_base + $last_successful_mirror) % $mirror_count ))
        mirror=${ZIGSH_MIRRORS[$mirror_index]}
        full_url="$mirror$path"
        logDebug "attempting to download $full_url"
        if ! result=$(curl -S -s --write-out "%{http_code}" ${curl_args[@]} "$full_url" 2>&3 ) ; then
            logDebug "download failed"
            continue
        fi
        if [ "$result" != "200" ]; then
            logDebug "download failed with non-200 status code $result"
            continue
        fi
        success=1
        successful_mirror=$mirror_index
        successful_mirror_index=$mirror_index_base
        
        logDebug "download succeeded"
        break
    done

    if [ "$success" == 1 ] && [ "$successful_mirror_index" != 0 ]; then
        logError "$successful_mirror_index mirrors failed before succeeeding - try reorganising the mirror list"
        # We keep track of this so that further fetches may have a greater chance of succeeding
        last_successful_mirror=$successful_mirror
    fi
    if [ "$success" == 0 ]; then
        rm $output_file
    fi

    if [ -n "$output_var" ]; then
        logDebug "variable $output_var"
        printf -v "$output_var" "$success"
    fi
}

# Resolves the version and stores it in $version_resolved
resolveZigVersion() {
    if [ "$ZIG_VERSION" == "master" ]; then
        logInfo "requested version is 'master' - this is discouraged as it requires work to resolve!"

        logError "TODO: resolve master version"
        exit 1
    else
        version_resolved=$ZIG_VERSION
    fi
}

verifySignatureOrExit() {
    file=$1
    pubkey=$2
    expected_file_field=$3

    logDebug "verifying signature for $file"
    logInfo "verifying signature"
        
    if ! trusted_comment=$(minisign -V -Q -P "$pubkey" -m "$file") ; then
        logError "${C_mark}$file${C_norm}'s signature is invalid!"
        exit 1
    fi

    sig_valid_file=0
    for field in ${trusted_comment[@]}; do
        case $field in
            file:*)
                IFS=':' read -ra field <<< $field
                if [ "${field[1]}" != "$expected_file_field" ]; then
                    logDebug "file field: ${field[1]}; expected: $expected_file_field"
                    logError "${C_mark}$file${C_norm}'s signature has an invalid file field"
                    exit 1
                fi
                sig_valid_file=1
                ;;
            *)
                ;;
        esac            
    done

    if [ $sig_valid_file == 0 ]; then
        logError "${C_mark}$file${C_norm}'s signature does not have a file: field in its trusted comment!"
        exit 1
    fi
}

zig_installed=0
downloadZig() {
    logInfo "downloading zig..."
    mkdir -p "$ZIG_BASE_DIR"
    # Determine which mirror is supposed to be used.
    if [ -z ${ZIGSH_MIRROR+x} ]; then
        if [ -z ${ZIGSH_MIRRORS+x} ] ; then
            ZIGSH_MIRRORS_TXT=${ZIGSH_MIRRORS_TXT:-$ZIG_BASE_DIR/community-mirrors.txt}
            ZIGSH_MIRRORS_TTL=${ZIGSH_MIRRORS_TTL:-1440}
            if [ $(find "$ZIGSH_MIRRORS_TXT" -mmin "-$ZIGSH_MIRRORS_TTL" -print 2> /dev/null ) ]; then
                ZIGSH_MIRRORS=$(cat $ZIGSH_MIRRORS_TXT)
            else
                logInfo "downloading mirrors list from ${C_mark}${ZIGSH_MIRRORS_URL:=https://ziglang.org/download/community-mirrors.txt}${C_norm}..."
                if ! curl -s -f --output "$ZIGSH_MIRRORS_TXT" "$ZIGSH_MIRRORS_URL" 2>&3 ; then
                    logError "could not download mirrors, using builtin list"
                    # ziglang.org/download/community-mirrors.txt (2026-07-17) 
                    ZIGSH_MIRRORS=(
                        "https://pkg.hexops.org/zig"
                        "https://zigmirror.hryx.net/zig"
                        "https://zig.linus.dev/zig"
                        "https://zig.squirl.dev"
                        "https://zig.mirror.mschae23.de/zig"
                        "https://ziglang.freetls.fastly.net"
                        "https://zig.tilok.dev"
                        "https://zig-mirror.tsimnet.eu/zig"
                        "https://zig.karearl.com/zig"
                        "https://pkg.earth/zig"
                        "https://fs.liujiacai.net/zigbuilds"
                        "https://zigmirror.com"
                        "https://zig.chainsafe.dev"
                        "https://zig.savalione.com"
                        "https://zig.bcr.ist"
                        "https://zig.vortan.dev/zig"
                    )
                else
                    shuf -o $ZIGSH_MIRRORS_TXT < $ZIGSH_MIRRORS_TXT
                    ZIGSH_MIRRORS=$(cat $ZIGSH_MIRRORS_TXT)
                fi
            fi
        fi
        # Ensure ZIGSH_MIRRORS is an array 
        readarray -t mirrors <<< "$ZIGSH_MIRRORS"
        ZIGSH_MIRRORS=( ${mirrors[@]} )
        logDebug "mirror list: ${ZIGSH_MIRRORS[*]}"
    fi

    resolveZigVersion
    
    case "$version_resolved" in
        0.[1-9].[0-9] | 0.1[0-3].[0-9] | 0.14.0)
            # Versions <=0.14.1 used this naming scheme for archives
            archive_name="zig-$operating_system-$architecture-$version_resolved.tar.xz"
            ;;
        *)
            archive_name="zig-$architecture-$operating_system-$version_resolved.tar.xz"
            ;;
    esac
    # archive_path is the file that would need to be affixed to ziglang.org for
    # it to resolve to the correct archive.
    case $version_resolved in
        *-dev.*)
            # Development versions are stored in /builds and not in a version
            # directory
            archive_path="/builds/$archive_name"
            ;;
        *)
            archive_path="/$version_resolved/$archive_name"
            ;;
    esac

    mkdir -p $ZIG_VERSIONED_DIR

    logInfo "downloading ${C_mark}$archive_name${C_norm}..."
    
    mirroredFetch -v archive_fetch_result -p "$archive_path" -o "$ZIG_BASE_DIR/$archive_name"
    
    if [ "$archive_fetch_result" != 1 ]; then
        logError "could not fetch archive; either the requested version does not exist, or it does not have a build for your platform"
        exit 1
    fi

    mirroredFetch -v archive_sig_fetch_result -p "$archive_path.minisig" -o "$ZIG_BASE_DIR/$archive_name.minisig"
    if [ "$archive_sig_fetch_result" != 1 ]; then
        logError "could not fetch archive signature, but archive could be fetched (this is strange)"
        exit 1
    fi
    
    verifySignatureOrExit "$ZIG_BASE_DIR/$archive_name" "$ZIG_MINISIGN_PUBKEY" "$archive_name"

    logInfo "extracting..."
    tar -xf "$ZIG_BASE_DIR/$archive_name" -C "$ZIG_VERSIONED_DIR" --strip-components=1
    rm "$ZIG_BASE_DIR/$archive_name" "$ZIG_BASE_DIR/$archive_name.minisig"

    # Add activation script to directory for convenience
    cat << EOF > "$ZIG_VERSIONED_DIR/activate.bash"
#!/usr/bin/bash
# This file was automatically generated by zig.sh
export PATH="\$( cd -- "\$( dirname -- "\${BASH_SOURCE[0]}" )" &> /dev/null && pwd )":\$PATH
EOF

    zig_installed=1
}

# If zig exists, don't download it.
# Allow overriding.
if [ ! -f "$ZIG_VERSIONED_DIR/zig" ] || [ ! -z ${ZIGSH_FORCE_DOWNLOAD+x} ]; then
    downloadZig
fi

# ZLS support

ZIGSH_ZLS_REPOSITORY=${ZIGSH_ZLS_REPOSITORY:="zigtools/zls"}

downloadZlsPrebuilt() {
    zls_release_tag=""
    zls_version_prefix=$(sed -n "s/^\(.\..*\)\..*$/\1/p" <<< "$version_resolved")
    if [ -z "$zls_version_prefix" ]; then
        logError "cannot determine appropriate major-minor version for ZLS"
        exit 1
    fi

    logInfo "finding appropriate ZLS version for ${C_mark}$zls_version_prefix.x${C_norm}..."
    zls_releases=$(curl -L -s --output "$ZIG_BASE_DIR/zls-releases.json" \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2026-03-10"    \
        "https://api.github.com/repos/$ZIGSH_ZLS_REPOSITORY/releases")

    zls_release_tags=($(sed -n "s/^.*\"tag_name\": \"\(.*\)\".*$/\1/p" < "$ZIG_BASE_DIR/zls-releases.json"))    
    for release_tag in ${zls_release_tags[@]} ; do
        # Check if $release_tag starts with $zls_version_prefix
        if [ ${release_tag#"$zls_version_prefix"} != $release_tag ] ; then
            zls_release_tag=$release_tag
            # Breaking here makes $zls_release_tag the first release that
            # GitHub puts in its response. Thankfully, the order of
            # releases in the response happens to be descending
            # chronologically.
            break
        fi 
    done
    

    if [ -z "$zls_release_tag" ]; then
        logInfo "no compatible ZLS release was found"
    fi
        
    logInfo "downloading ZLS ${C_mark}$zls_release_tag${C_norm}..."

    # Figure out what the archive's name on the server is, and what it should
    # be locally.
    case "$zls_release_tag" in
        0.[0-9].[0-9])
            archive_name_remote="$architecture-$operating_system.tar.xz"
            archive_name="zls-$architecture-$operating_system-$zls_release_tag.tar.xz"
            ;;
        0.10.0)
            archive_name_remote="$architecture-$operating_system.tar.zst"
            archive_name="zls-$architecture-$operating_system-$zls_release_tag.tar.zst"
            ;;
        0.11.0)
            archive_name_remote="zls-$architecture-$operating_system.tar.gz"
            archive_name="zls-$architecture-$operating_system-$zls_release_tag.tar.gz"
            ;;
        *)
            archive_name_remote="zls-$architecture-$operating_system.tar.xz"
            archive_name="zls-$architecture-$operating_system-$zls_release_tag.tar.xz"
            ;;
    esac
    release_base_url="https://github.com/$ZIGSH_ZLS_REPOSITORY/releases/download/$zls_release_tag"
    curl_args=("-L" "-s" "-f" "-S" "-o" "$ZIG_BASE_DIR/$archive_name" "$release_base_url/$archive_name_remote")
    if [ -n "$zls_minisign_pubkey" ]; then
        curl_args=(${curl_args[@]} -o "$ZIG_BASE_DIR/$archive_name.minisig" "$release_base_url/$archive_name_remote.minisig")
    fi
    
    if ! fetch_result=$(curl --write-out "%{http_code}" ${curl_args[@]}); then
        logDebug "fetch result: $fetch_result"
        logError "failed to fetch release archive; building from source"
        return
    fi

    errored=0
    for result in ${fetch_result[@]}; do
        if [ "$result" == "200" ]; then
            logDebug "ZLS download failed with status $result"
            errored=1
        fi
    done
    if [ "$errored" == 1 ]; then
        logError "failed to fetch release archive; building from source"
        return
    fi

    if [ -n "$zls_minisign_pubkey" ]; then
        verifySignatureOrExit "$ZIG_BASE_DIR/$archive_name" "$zls_minisign_pubkey" "$archive_name"
    fi

    logInfo "extracting..."
    # Be careful not to overwrite any of the text files
    tar -xf "$ZIG_BASE_DIR/$archive_name" -C "$ZIG_VERSIONED_DIR/doc-zls"
    mv "$ZIG_VERSIONED_DIR/doc-zls/zls" "$ZIG_VERSIONED_DIR/"

    zls_installed=1
}

buildZlsFromSource() {
    # TODO: Make this support other commits than master
    logError "building ZLS from source is not yet supported"
    exit 1
}

zls_installed=0
installZls() {
    if [ "${ZIGSH_NO_ZLS:=0}" != 0 ]; then return; fi 
    
    resolveZigVersion

    # Determine which pubkey the release should be signed by (if any)
    zls_minisign_pubkey="RWR+9B91GBZ0zOjh6Lr17+zKf5BoSuFvrx2xSeDE57uIYvnKBGmMjOex"
    case "$version_resolved" in
        # Versions <=0.13 do not have signatures
        0.[1-9].[1-9] | 0.1[0-3].[0-9])
            zls_minisign_pubkey=""
            ;;
        # For all other versions we default to whatever key was last used
        *)
            ;;
    esac

    if [ ${ZIGSH_ZLS_NO_PREBUILD:=0} == 0 ]; then
        # Determine how to download ZLS
        case "$version_resolved" in
            # Nightly builds have to be built from source regardless
            *-dev.*)
                logInfo "zig version is a nightly build - building ZLS from source"
                ;;
            *)
                downloadZlsPrebuilt
                ;;
        esac
    else
        logInfo "${C_mark}ZIGSH_ZLS_NO_PREBUILD${C_norm} is set - building ZLS from source"
    fi

    if [ "$zls_installed" == 0 ]; then
        buildZlsFromSource
    fi

    exit 1
}

if [ ! -f "$ZIG_VERSIONED_DIR/zls" ] || [ ! -z ${ZIGSH_FORCE_DOWNLOAD+x} ]; then
    installZls
fi

if [ "$zig_installed" == 1 ] || [ "$zls_installed" == 1 ]; then
    logInfo "done! enjoy programming in Zig ${C_mark}<3"
fi

if [ "${ZIGSH_ONLY_INSTALL:=0}" != 0 ]; then
    logDebug "ZIGSH_ONLY_INSTALLED is set - exiting soon"
    if [ "$zig_installed" == 0 ] && [ "$zls_installed" == 0 ]; then
        logInfo "Zig is already installed"
    fi
    exit 0
fi

"$ZIG_VERSIONED_DIR/zig" $@
