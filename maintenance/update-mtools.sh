#!/usr/bin/env bash

set -euo pipefail

function usage() {
    cat <<EOF
Usage:
    update-mtools.sh [--commit] [--pr]

Options:
    --commit      create or update the maintenance branch commit.
    --pr          implies --commit, pushes, and creates or updates a GitHub PR.
EOF
}

commit_mode=0
pr_mode=0

for arg in "$@"
do
    case "${arg}" in
        --commit)
            commit_mode=1
            ;;
        --pr)
            pr_mode=1
            commit_mode=1
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: ${arg}."
            usage
            exit 1
            ;;
    esac
done

source_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
repo_root="$(cd "${source_dir}/.." &> /dev/null && pwd)"
config_file="${repo_root}/toolchain/config.cmake"

source "${source_dir}/update-common.sh"

starting_branch=$(git -C "${repo_root}" branch --show-current)
archive_path=""

if [[ ${commit_mode} -eq 1 ]]
then
    if [[ -z "${starting_branch}" ]]
    then
        echo "A named target branch is required when creating a tool update."
        exit 1
    fi
    update_require_clean_worktree "${repo_root}"
fi

function switch_back() {
    local current_branch
    current_branch=$(git -C "${repo_root}" branch --show-current)
    if [[ -n "${starting_branch}" && "${current_branch}" != "${starting_branch}" ]]
    then
        git -C "${repo_root}" checkout "${starting_branch}" >/dev/null 2>&1 || true
    fi
    if [[ -n "${archive_path}" ]]
    then
        rm -f "${archive_path}"
    fi
}
trap switch_back EXIT

mtools_dir=$(update_get_config_value "${config_file}" "REAVEROS_MTOOLS_DIR")
current_version=$(update_get_config_value "${config_file}" "REAVEROS_MTOOLS_VER")
current_sha256=$(update_get_config_value "${config_file}" "REAVEROS_MTOOLS_SHA256")
version_pattern=$(update_get_config_value "${config_file}" "REAVEROS_MTOOLS_PATTERN")
version_exclude=$(update_get_config_value "${config_file}" "REAVEROS_MTOOLS_EXCLUDE")

latest_version=$(curl \
    --fail \
    --silent \
    --show-error \
    --location \
    --retry 3 \
    --retry-all-errors \
    --connect-timeout 30 \
    --max-time 120 \
    "${mtools_dir}/" \
    | sed -nE 's/.*href="([^"]+)".*/\1/p' \
    | grep -E "^${version_pattern}$")

if [[ -n "${version_exclude}" ]]
then
    latest_version=$(printf "%s\n" "${latest_version}" | grep -Ev "^${version_exclude}$")
fi

latest_version=$(printf "%s\n" "${latest_version}" | sort -V | tail -n1)

if [[ -z "${latest_version}" ]]
then
    echo "Could not determine latest mtools version."
    exit 1
fi

if [[ "${current_version}" == "${latest_version}" ]]
then
    exit 0
fi

echo "mtools: upgrade available: ${current_version} -> ${latest_version}"

if [[ ${commit_mode} -eq 0 ]]
then
    exit 0
fi

archive_path=$(update_make_temp_file "mtools-archive")
curl \
    --fail \
    --silent \
    --show-error \
    --location \
    --retry 3 \
    --retry-all-errors \
    --connect-timeout 30 \
    --max-time 120 \
    --output "${archive_path}" \
    "${mtools_dir}/${latest_version}"
latest_sha256=$(sha256sum "${archive_path}" | awk '{ print $1 }')

base_branch="${starting_branch}"
base_branch_component=$(update_sanitize_branch_component "${base_branch}")
update_branch="maintenance/update/mtools/${base_branch_component}/${latest_version}"

known_remote=0
if update_is_known_reaveros_remote "${repo_root}"
then
    known_remote=1
else
    if [[ ${pr_mode} -eq 1 ]]
    then
        echo "Refusing to publish to an unrecognized repository remote." >&2
        exit 1
    fi
fi

if [[ ${commit_mode} -eq 1 && ${pr_mode} -eq 0 \
    && ${REAVEROS_MAINTENANCE_CI:-0} == 1 \
    && ${known_remote} -eq 1 ]]
then
    existing_status=0
    update_existing_branch_is_current \
        "${repo_root}" "${update_branch}" "${base_branch}" \
        || existing_status=$?
    if [[ ${existing_status} -eq 0 ]]
    then
        echo "Current update PR already exists for mtools; skipping."
        exit 0
    elif [[ ${existing_status} -ne 1 ]]
    then
        echo "Could not inspect the existing mtools update." >&2
        exit 1
    fi
fi

if [[ ${pr_mode} -eq 1 && ${known_remote} -eq 1 ]] && update_remote_branch_exists "${repo_root}" "${update_branch}"
then
    update_require_gh
    update_reconcile_existing_branch "${repo_root}" "${update_branch}" "${base_branch}"

    if [[ "${update_existing_branch_action}" == "skip" ]]
    then
        echo "Remote branch ${update_branch} already has an active PR, skipping."
        exit 0
    fi

    if [[ "${update_existing_branch_action}" == "blocked" ]]
    then
        echo "Remote branch ${update_branch} has an active PR with failed checks."
        exit 1
    fi

    echo "Rebuilding ${update_branch} from ${base_branch}."
fi

if git -C "${repo_root}" show-ref --verify --quiet "refs/heads/${update_branch}"
then
    if ! git -C "${repo_root}" merge-base --is-ancestor \
        "${base_branch}" "${update_branch}"
    then
        echo "Local update branch ${update_branch} predates ${base_branch}; refusing to reuse it." >&2
        exit 1
    fi
    git -C "${repo_root}" checkout "${update_branch}"
else
    # A stale remote PR must be rebuilt from the current target branch, not
    # from its already-updated remote head.
    git -C "${repo_root}" checkout -b "${update_branch}" "${base_branch}"
fi

sed -i -E "s#^set\\(REAVEROS_MTOOLS_VER [^)]+\\)#set(REAVEROS_MTOOLS_VER ${latest_version})#" "${config_file}"
sed -i -E "s#^set\\(REAVEROS_MTOOLS_SHA256 [^)]+\\)#set(REAVEROS_MTOOLS_SHA256 ${latest_sha256})#" "${config_file}"

git -C "${repo_root}" add "toolchain/config.cmake"
update_require_only_staged_paths "${repo_root}" "toolchain/config.cmake"

commit_message_path=$(update_make_temp_file "commit-message-mtools")
{
    echo "Update toolchain tool mtools from ${current_version} to ${latest_version}."
    echo
    echo "Old SHA-256: ${current_sha256}"
    echo "New SHA-256: ${latest_sha256}"
} > "${commit_message_path}"

if git -C "${repo_root}" diff --cached --quiet
then
    echo "No repository changes to commit for mtools."
else
    git -C "${repo_root}" -c commit.gpgsign=false commit --no-gpg-sign \
        --file "${commit_message_path}"
fi

rm -f "${commit_message_path}"
update_record_branch "${update_branch}"

if [[ ${pr_mode} -eq 0 ]]
then
    exit 0
fi

if [[ ${known_remote} -eq 0 ]]
then
    exit 0
fi

update_require_gh
published_revision=$("${source_dir}/publish-signed-update" \
    "${repo_root}" "${update_branch}" "${base_branch}")

pr_title="Update toolchain tool mtools from ${current_version} to ${latest_version}."
pr_body_path=$(update_make_temp_file "pr-body-mtools")

{
    echo "## Toolchain Tool Update"
    echo
    echo "- Tool: mtools"
    echo "- Old version: ${current_version}"
    echo "- New version: ${latest_version}"
    echo "- Old SHA-256: \`${current_sha256}\`"
    echo "- New SHA-256: \`${latest_sha256}\`"
} > "${pr_body_path}"

update_upsert_pr "${update_branch}" "${base_branch}" "${pr_title}" "${pr_body_path}"

update_enable_auto_merge "${update_pr_number}" "${published_revision}"

rm -f "${pr_body_path}"
