#!/usr/bin/env bash

set -euo pipefail

function usage() {
    cat <<EOF
Usage:
    update-git.sh <tool> [--commit] [--pr] [--continue] [--amend]

Options:
    --commit      create or update the maintenance branch commit.
    --pr          implies --commit, pushes, and creates or updates a GitHub PR.
    --continue    resume a blocked refresh, reconstructing a missing checkout.
                  Resolve any recreated conflict and rerun; the update is amended.
    --amend       amend the previous update commit instead of creating a new one.
EOF
}

if [[ $# -eq 1 && ( "$1" == "--help" || "$1" == "-h" ) ]]
then
    usage
    exit 0
fi

if [[ $# -lt 1 ]]
then
    usage
    exit 1
fi

tool_lc=${1,,}
tool_uc=${tool_lc^^}
shift

case "${tool_lc}" in
    cmake|llvm|dosfstools) ;;
    *) echo "Unsupported Git-backed tool: ${tool_lc}." >&2; exit 2 ;;
esac

pr=0
commit_mode=0
continue_mode=0
amend_mode=0

for arg in "$@"
do
    case "$arg" in
        --pr)
            pr=1
            commit_mode=1
            ;;
        --commit)
            commit_mode=1
            ;;
        --continue)
            continue_mode=1
            ;;
        --amend)
            amend_mode=1
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

if [[ ${continue_mode} -eq 1 && ${commit_mode} -eq 0 ]]
then
    echo "--continue requires --commit (or --pr)."
    exit 1
fi

# A resumed update must replace its incomplete preparation commit. Appending a
# second commit would make the unsigned first commit a parent of publication.
if [[ ${continue_mode} -eq 1 ]]
then
    amend_mode=1
fi

if [[ ${amend_mode} -eq 1 && ${commit_mode} -eq 0 ]]
then
    echo "--amend requires --commit (or --pr)."
    exit 1
fi

source_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
repo_root="$(cd "${source_dir}/.." &> /dev/null && pwd)"
config_file="${repo_root}/toolchain/config.cmake"
state_dir="${repo_root}/maintenance/update-state"
state_file="${state_dir}/${tool_lc}.state"
checkout_dir="${repo_root}/build/maintenance/toolchain-checkouts/${tool_lc}"

source "${source_dir}/update-common.sh"

starting_branch=$(git -C "${repo_root}" branch --show-current)

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
}
trap switch_back EXIT

function get_config_value() {
    local key="$1"
    update_get_config_value "${config_file}" "REAVEROS_${tool_uc}_${key}"
}

function normalize_patch() {
    sed -E 's/^index [0-9a-f]+\.\.[0-9a-f]+( [0-9]+)?$/index <hash>..<hash>\1/'
}

function list_patch_files() {
    patch_files=()
    mapfile -d '' -t patch_files < <(
        git -C "${repo_root}" ls-files -z -- \
            "toolchain/${tool_lc}/patches/*.patch" | sort -z
    )
    local patch
    for patch in "${patch_files[@]}"
    do
        if [[ ${patch#toolchain/${tool_lc}/patches/} == */* ]]
        then
            echo "Nested patch path is not supported: ${patch}." >&2
            exit 1
        fi
    done
}

function set_config_tag() {
    local target_tag="$1"
    sed -i -E "s#^set\\(REAVEROS_${tool_uc}_TAG [^)]+\\)#set(REAVEROS_${tool_uc}_TAG ${target_tag})#" "${config_file}"
}

function set_config_revision() {
    local target_revision="$1"

    if grep -q "^set(REAVEROS_${tool_uc}_REVISION " "${config_file}"
    then
        sed -i -E "s#^set\\(REAVEROS_${tool_uc}_REVISION [^)]+\\)#set(REAVEROS_${tool_uc}_REVISION ${target_revision})#" "${config_file}"
    else
        sed -i -E "/^set\\(REAVEROS_${tool_uc}_TAG /a set(REAVEROS_${tool_uc}_REVISION ${target_revision})" "${config_file}"
    fi
}

function get_llvm_source_digest() {
    local target_tag="$1"
    update_require_gh
    local source_version=${target_tag#llvmorg-}
    local asset_name="llvm-project-${source_version}.src.tar.xz"
    local digest
    digest=$(gh api "repos/llvm/llvm-project/releases/tags/${target_tag}" \
        --jq ".assets[] | select(.name == \"${asset_name}\") | .digest")
    if [[ ! "${digest}" =~ ^sha256:[0-9a-f]{64}$ ]]
    then
        echo "The official LLVM release asset ${asset_name} has no SHA-256 digest." >&2
        return 1
    fi

    printf '%s' "${digest#sha256:}"
}

function set_llvm_source_digest() {
    if [[ "${tool_lc}" != "llvm" ]]
    then
        return
    fi

    if [[ ! "${new_source_digest}" =~ ^[0-9a-f]{64}$ ]]
    then
        echo "The LLVM update has no pinned release-archive digest." >&2
        exit 1
    fi

    sed -i -E \
        "s#^set\\(REAVEROS_LLVM_SOURCE_SHA256 [^)]+\\)#set(REAVEROS_LLVM_SOURCE_SHA256 ${new_source_digest})#" \
        "${config_file}"
}

function ensure_checkout() {
    mkdir -p "$(dirname "${checkout_dir}")"
    reconstructed_checkout=0

    if [[ ${continue_mode} -eq 1 ]]
    then
        if [[ ! -d "${checkout_dir}/.git" ]]
        then
            reconstructed_checkout=1
            git clone \
                --depth 1 \
                --single-branch \
                --no-tags \
                --branch "${old_tag}" \
                "${repo}" \
                "${checkout_dir}"
        fi
    elif [[ ! -d "${checkout_dir}/.git" ]]
    then
        git clone \
            --depth 1 \
            --single-branch \
            --no-tags \
            --branch "${old_tag}" \
            "${repo}" \
            "${checkout_dir}"
    else
        git -C "${checkout_dir}" cherry-pick --abort >/dev/null 2>&1 || true
        git -C "${checkout_dir}" reset --hard >/dev/null
        git -C "${checkout_dir}" clean -fdx >/dev/null
    fi

    if [[ ${continue_mode} -eq 0 || ${reconstructed_checkout} -eq 1 ]]
    then
        if [[ "${old_tag}" == "${new_tag}" ]]
        then
            git -C "${checkout_dir}" fetch --depth 1 --no-tags origin \
                "+refs/tags/${old_tag}:refs/tags/${old_tag}"
        else
            git -C "${checkout_dir}" fetch --depth 1 --no-tags origin \
                "+refs/tags/${old_tag}:refs/tags/${old_tag}" \
                "+refs/tags/${new_tag}:refs/tags/${new_tag}"
        fi
    fi

    local actual_old_revision
    local actual_new_revision
    actual_old_revision=$(git -C "${checkout_dir}" rev-parse "${old_tag}^{commit}")
    actual_new_revision=$(git -C "${checkout_dir}" rev-parse "${new_tag}^{commit}")

    if [[ "${actual_old_revision}" != "${old_revision}" ]]
    then
        echo "Tag ${old_tag} resolved to ${actual_old_revision}, expected ${old_revision}."
        exit 1
    fi

    if [[ "${actual_new_revision}" != "${new_revision}" ]]
    then
        echo "Tag ${new_tag} resolved to ${actual_new_revision}, expected ${new_revision}."
        exit 1
    fi

    if [[ ${reconstructed_checkout} -eq 1 ]]
    then
        reconstruct_checkout
    fi
}

function source_git() {
    git -C "${checkout_dir}" -c commit.gpgsign=false "$@"
}

function reconstruct_checkout() {
    if [[ $(git -C "${repo_root}" rev-parse HEAD^) \
        != $(git -C "${repo_root}" rev-parse "${base_branch}") ]]
    then
        echo "Cannot reconstruct an update not based on current ${base_branch}." >&2
        exit 1
    fi
    if [[ -z ${failed_patch} ]]
    then
        echo "Cannot reconstruct an update without a recorded failed patch." >&2
        exit 1
    fi

    git -C "${checkout_dir}" checkout -B "${old_work_branch}" "${old_revision}"
    for patch in "${patch_files[@]}"
    do
        if ! git -C "${checkout_dir}" apply \
            <(git -C "${repo_root}" show "HEAD^:${patch}")
        then
            echo "Could not reconstruct the original ${patch}." >&2
            exit 1
        fi
        git -C "${checkout_dir}" add -A
        source_git commit --allow-empty -m "reaveros-maintenance: ${patch}" > /dev/null
        patch_source_commit["${patch}"]=$(git -C "${checkout_dir}" rev-parse HEAD)
    done

    git -C "${checkout_dir}" checkout -B "${new_work_branch}" "${new_revision}"
    for patch in "${patch_files[@]}"
    do
        if [[ ${patch_phase_status[${patch}]:-pending} == applied ]]
        then
            if ! git -C "${checkout_dir}" apply "${repo_root}/${patch}"
            then
                echo "Could not reconstruct the refreshed ${patch}." >&2
                exit 1
            fi
            git -C "${checkout_dir}" add -A
            if git -C "${checkout_dir}" diff --cached --quiet
            then
                echo "Reconstructed patch ${patch} has no changes." >&2
                exit 1
            fi
            source_git commit -m "reaveros-maintenance: ${patch}" > /dev/null
            patch_cherry_commit["${patch}"]=$(git -C "${checkout_dir}" rev-parse HEAD)
        elif [[ ${patch} == "${failed_patch}" ]]
        then
            if source_git cherry-pick --keep-redundant-commits \
                "${patch_source_commit[${patch}]}" > /dev/null 2>&1 \
                || [[ ! -f "${checkout_dir}/.git/CHERRY_PICK_HEAD" ]]
            then
                echo "Could not recreate the recorded conflict in ${patch}." >&2
                exit 1
            fi
            break
        fi
    done

    write_state
    git -C "${repo_root}" add "maintenance/update-state/${tool_lc}.state"
    update_require_only_staged_paths "${repo_root}" \
        "maintenance/update-state/${tool_lc}.state"
    git -C "${repo_root}" -c commit.gpgsign=false commit --amend \
        --no-gpg-sign --no-edit > /dev/null
    echo "Reconstructed the ${tool_lc} conflict at ${checkout_dir}. Resolve it, then rerun --continue." >&2
}

function get_latest_tag() {
    local latest

    latest=$(printf '%s\n' "${remote_tags}" \
        | awk '{ print $2 }' | sed 's:refs/tags/::' \
        | grep -E "^${tag_pattern}(\^\{\})?$")

    if [[ -n "${tag_exclude}" ]]
    then
        latest=$(printf "%s\n" "${latest}" | grep -Ev "^${tag_exclude}(\^\{\})?$")
    fi

    latest=$(printf "%s\n" "${latest}" | sort -V | sed 's/\^{}//' | tail -n1)
    printf "%s" "${latest}"
}

function get_tag_revision() {
    local target_tag="$1"
    local direct_ref="refs/tags/${target_tag}"
    local peeled_ref="refs/tags/${target_tag}^{}"
    local revision

    revision=$(printf '%s\n' "${remote_tags}" \
        | awk -v ref="${peeled_ref}" '$2 == ref { print $1; exit }')

    if [[ -z "${revision}" ]]
    then
        revision=$(printf '%s\n' "${remote_tags}" \
            | awk -v ref="${direct_ref}" '$2 == ref { print $1; exit }')
    fi

    if [[ ! "${revision}" =~ ^[0-9a-f]{40}$ ]]
    then
        echo "Could not resolve tag ${target_tag} to a commit." >&2
        return 1
    fi

    printf '%s' "${revision}"
}

function ensure_update_branch_checked_out() {
    local base_for_new="$1"

    if git -C "${repo_root}" show-ref --verify --quiet "refs/heads/${update_branch}"
    then
        if ! git -C "${repo_root}" merge-base --is-ancestor \
            "${base_for_new}" "${update_branch}"
        then
            echo "Local update branch ${update_branch} predates ${base_for_new}; refusing to reuse it." >&2
            exit 1
        fi
        git -C "${repo_root}" checkout "${update_branch}"
        return
    fi

    if [[ ${continue_mode} -eq 1 || ${amend_mode} -eq 1 ]]
    then
        if [[ ${known_remote} -eq 1 ]] && update_remote_branch_exists "${repo_root}" "${update_branch}"
        then
            git -C "${repo_root}" fetch origin \
                "refs/heads/${update_branch}:refs/remotes/origin/${update_branch}"
            if ! git -C "${repo_root}" merge-base --is-ancestor \
                "${base_for_new}" "origin/${update_branch}"
            then
                echo "Remote update branch ${update_branch} predates ${base_for_new}; refusing to reuse it." >&2
                exit 1
            fi
            git -C "${repo_root}" checkout -b "${update_branch}" "origin/${update_branch}"
            return
        fi
    fi

    if [[ ${continue_mode} -eq 1 || ${amend_mode} -eq 1 ]]
    then
        echo "Cannot continue/amend: local and remote branch '${update_branch}' do not exist."
        exit 1
    fi

    git -C "${repo_root}" checkout -b "${update_branch}" "${base_for_new}"
}

function checkout_continue_update_branch() {
    local branch_prefix="maintenance/update/${tool_lc}/"
    local state_path="maintenance/update-state/${tool_lc}.state"
    local current_branch
    local candidate_ref
    local candidate_base
    local local_branch

    current_branch=$(git -C "${repo_root}" branch --show-current)

    if [[ "${current_branch}" == ${branch_prefix}* ]] \
       && git -C "${repo_root}" cat-file -e "${current_branch}:${state_path}" 2>/dev/null
    then
        return
    fi

    while IFS= read -r candidate_ref
    do
        if [[ -z "${candidate_ref}" ]]
        then
            continue
        fi

        if ! git -C "${repo_root}" cat-file -e "${candidate_ref}:${state_path}" 2>/dev/null
        then
            continue
        fi

        candidate_base=$(git -C "${repo_root}" show "${candidate_ref}:${state_path}" \
            | sed -n 's/^base_branch=//p' | head -n1)
        if [[ -n "${candidate_base}" && "${candidate_base}" != "${starting_branch}" ]]
        then
            continue
        fi

        if [[ "${candidate_ref}" == origin/* ]]
        then
            local_branch=${candidate_ref#origin/}
            if git -C "${repo_root}" show-ref --verify --quiet "refs/heads/${local_branch}"
            then
                git -C "${repo_root}" checkout "${local_branch}"
            else
                git -C "${repo_root}" checkout -b "${local_branch}" "${candidate_ref}"
            fi
        else
            git -C "${repo_root}" checkout "${candidate_ref}"
        fi
        return
    done < <(git -C "${repo_root}" for-each-ref \
        --sort=-committerdate \
        --format='%(refname:short)' \
        "refs/heads/${branch_prefix}" \
        "refs/remotes/origin/${branch_prefix}")

    echo "Cannot continue: could not find a maintenance branch matching ${branch_prefix}* with ${state_path}."
    exit 1
}

function refresh_patch_summary_lists() {
    updated_patches=()
    unchanged_patches=()
    unresolved_patches=()

    for patch in "${patch_files[@]}"
    do
        local phase_status="${patch_phase_status[${patch}]:-pending}"
        local file_status="${patch_file_status[${patch}]:-not-updated}"

        if [[ "${phase_status}" != "applied" ]]
        then
            unresolved_patches+=("${patch}")
        fi

        if [[ "${file_status}" == "updated" ]]
        then
            updated_patches+=("${patch}")
        fi

        if [[ "${file_status}" == "unchanged" ]]
        then
            unchanged_patches+=("${patch}")
        fi
    done
}

function has_redundant_patch() {
    local patch
    for patch in "${patch_files[@]}"
    do
        if [[ ${patch_resolution[${patch}]:-} == redundant ]]
        then
            return 0
        fi
    done
    return 1
}

function write_state() {
    refresh_patch_summary_lists

    if [[ ${#unresolved_patches[@]} -eq 0 ]]
    then
        failed_patch=""
        rm -f "${state_file}"
        return
    fi

    mkdir -p "${state_dir}"

    {
        echo "state_version=5"
        echo "tool=${tool_lc}"
        echo "base_branch=${base_branch}"
        echo "update_branch=${update_branch}"
        echo "old_tag=${old_tag}"
        echo "new_tag=${new_tag}"
        echo "old_revision=${old_revision}"
        echo "new_revision=${new_revision}"
        if [[ "${tool_lc}" == "llvm" ]]
        then
            echo "new_source_digest=${new_source_digest}"
        fi
        if [[ -n ${REAVEROS_COPILOT_PATCH_CONFLICT_RESOLVER:-} ]]
        then
            echo "copilot_model=${REAVEROS_COPILOT_MODEL:-auto}"
        fi
        echo "old_work_branch=${old_work_branch}"
        echo "new_work_branch=${new_work_branch}"
        echo "status=incomplete"
        echo "failed_patch=${failed_patch}"
        echo "unresolved_count=${#unresolved_patches[@]}"

        for patch in "${patch_files[@]}"
        do
            local source_commit="${patch_source_commit[${patch}]:--}"
            local cherry_commit="${patch_cherry_commit[${patch}]:--}"
            local phase_status="${patch_phase_status[${patch}]:-pending}"
            local file_status="${patch_file_status[${patch}]:-not-updated}"
            local resolution="${patch_resolution[${patch}]:-pending}"
            echo "patch|${patch}|${source_commit}|${cherry_commit}|${phase_status}|${file_status}|${resolution}"
        done
    } > "${state_file}"
}

function read_state() {
    if [[ ! -f "${state_file}" ]]
    then
        echo "Cannot continue: state file does not exist: ${state_file}."
        exit 1
    fi

    local state_tool=""
    local state_version=""

    patch_files=()
    patch_source_commit=()
    patch_cherry_commit=()
    patch_phase_status=()
    patch_file_status=()
    patch_resolution=()

    while IFS= read -r line || [[ -n "${line}" ]]
    do
        case "${line}" in
            state_version=*)
                state_version=${line#*=}
                ;;
            tool=*)
                state_tool=${line#*=}
                ;;
            base_branch=*)
                base_branch=${line#*=}
                ;;
            update_branch=*)
                update_branch=${line#*=}
                ;;
            old_tag=*)
                old_tag=${line#*=}
                ;;
            new_tag=*)
                new_tag=${line#*=}
                ;;
            old_revision=*)
                old_revision=${line#*=}
                ;;
            new_revision=*)
                new_revision=${line#*=}
                ;;
            new_source_digest=*)
                new_source_digest=${line#*=}
                ;;
            old_work_branch=*)
                old_work_branch=${line#*=}
                ;;
            new_work_branch=*)
                new_work_branch=${line#*=}
                ;;
            failed_patch=*)
                failed_patch=${line#*=}
                ;;
            patch\|*)
                IFS='|' read -r _ patch source_commit cherry_commit phase_status file_status resolution <<< "${line}"
                patch_files+=("${patch}")
                patch_source_commit["${patch}"]="${source_commit}"
                patch_cherry_commit["${patch}"]="${cherry_commit}"
                patch_phase_status["${patch}"]="${phase_status}"
                patch_file_status["${patch}"]="${file_status}"
                if [[ -n "${resolution}" ]]
                then
                    patch_resolution["${patch}"]="${resolution}"
                elif [[ "${phase_status}" == "applied" ]]
                then
                    patch_resolution["${patch}"]="unknown"
                else
                    patch_resolution["${patch}"]="pending"
                fi
                ;;
            *)
                ;;
        esac
    done < "${state_file}"

    if [[ "${state_tool}" != "${tool_lc}" ]]
    then
        echo "Cannot continue: state file is for tool '${state_tool}', expected '${tool_lc}'."
        exit 1
    fi

    if [[ "${state_version}" != "5" ]]
    then
        echo "Cannot continue: unsupported state version '${state_version}'."
        exit 1
    fi

    for patch in "${patch_files[@]}"
    do
        if [[ "${patch_source_commit[${patch}]}" == "-" ]]
        then
            patch_source_commit["${patch}"]=""
        fi
        if [[ "${patch_cherry_commit[${patch}]}" == "-" ]]
        then
            patch_cherry_commit["${patch}"]=""
        fi
    done

    if [[ -z "${base_branch}" ]]
    then
        base_branch=${starting_branch}
    fi
}

function append_previous_coauthors() {
    local commit_message_file="$1"
    local previous_author
    local previous_body
    local current_author
    declare -A seen_contributors=()
    local contributors=()

    if ! git -C "${repo_root}" rev-parse --verify -q HEAD >/dev/null
    then
        echo "Cannot amend: no existing commit on branch ${update_branch}."
        exit 1
    fi

    previous_author=$(git -C "${repo_root}" log -1 --format='%an <%ae>')
    previous_body=$(git -C "${repo_root}" log -1 --format='%B')
    current_author=$(git -C "${repo_root}" var GIT_AUTHOR_IDENT \
        | sed -E 's/ [0-9]+ [+-][0-9]{4}$//')

    if [[ -n "${previous_author}" ]]
    then
        seen_contributors["${previous_author}"]=1
        contributors+=("${previous_author}")
    fi

    while IFS= read -r line
    do
        if [[ "${line}" =~ ^Co-authored-by:[[:space:]]*(.+)$ ]]
        then
            contributor="${BASH_REMATCH[1]}"
            if [[ -z "${seen_contributors[${contributor}]+x}" ]]
            then
                seen_contributors["${contributor}"]=1
                contributors+=("${contributor}")
            fi
        fi
    done <<< "${previous_body}"

    for contributor in "${contributors[@]}"
    do
        if [[ "${contributor}" != "${current_author}" ]]
        then
            echo "Co-authored-by: ${contributor}" >> "${commit_message_file}"
        fi
    done
}

function build_commit_message() {
    local output_file="$1"

    refresh_patch_summary_lists

    {
        echo "Update toolchain tool ${tool_lc} from ${old_tag} to ${new_tag}."
        echo
        echo "Patch refresh summary:"
        echo "- Total patch files: ${#patch_files[@]}"
        echo "- Updated patch files: ${#updated_patches[@]}"
        echo "- Unchanged patch files: ${#unchanged_patches[@]}"
        echo "- Unresolved patch files: ${#unresolved_patches[@]}"
        echo
        echo "Patch resolution methods:"
        if [[ ${#patch_files[@]} -eq 0 ]]
        then
            echo "- (none)"
        else
            for patch in "${patch_files[@]}"
            do
                echo "- ${patch}: ${patch_resolution[${patch}]:-pending}"
            done
        fi
        echo
        echo "Patch files requiring manual follow-up (not applied cleanly):"
        if [[ ${#unresolved_patches[@]} -eq 0 ]]
        then
            echo "- (none)"
        else
            for patch in "${unresolved_patches[@]}"
            do
                echo "- ${patch}"
            done
        fi
        echo
        if [[ ${#unresolved_patches[@]} -gt 0 ]]
        then
            echo "State file: maintenance/update-state/${tool_lc}.state"
            if has_redundant_patch
            then
                echo "A patch is already upstream. Remove its file and toolchain build-definition reference in a separate reviewed PR targeting ${base_branch}; rerun maintenance to supersede this blocked PR."
            fi
        else
            echo "State file: (none; update is complete)"
        fi
    } > "${output_file}"

    if [[ ${amend_mode} -eq 1 ]]
    then
        echo >> "${output_file}"
        append_previous_coauthors "${output_file}"
    fi
}

function build_pr_body() {
    local output_file="$1"

    refresh_patch_summary_lists

    {
        echo "## Toolchain Tool Update"
        echo
        echo "- Tool: ${tool_lc}"
        echo "- Old version: ${old_tag}"
        echo "- New version: ${new_tag}"
        echo "- Old revision: \`${old_revision}\`"
        echo "- New revision: \`${new_revision}\`"
        if [[ -n ${REAVEROS_COPILOT_PATCH_CONFLICT_RESOLVER:-} ]]
        then
            echo "- Copilot conflict model: ${REAVEROS_COPILOT_MODEL:-auto}"
        fi
        echo "- Total patch files: ${#patch_files[@]}"
        echo "- Updated patch files: ${#updated_patches[@]}"
        echo "- Unchanged patch files: ${#unchanged_patches[@]}"
        echo "- Unresolved patch files: ${#unresolved_patches[@]}"
        echo
        echo "## Patch Resolution Methods"
        echo
        if [[ ${#patch_files[@]} -eq 0 ]]
        then
            echo "- (none)"
        else
            for patch in "${patch_files[@]}"
            do
                echo "- \`${patch}\`: ${patch_resolution[${patch}]:-pending}"
            done
        fi
        echo
        echo "## Patch Files Requiring Manual Follow-up"
        echo
        if [[ ${#unresolved_patches[@]} -eq 0 ]]
        then
            echo "- (none)"
        else
            for patch in "${unresolved_patches[@]}"
            do
                echo "- ${patch}"
            done
        fi
        echo
        echo "## State"
        echo
        if [[ ${#unresolved_patches[@]} -gt 0 ]]
        then
            echo "- State file: maintenance/update-state/${tool_lc}.state"
            echo "- The CI workflow intentionally fails fast while unresolved patches remain."
            if has_redundant_patch
            then
                echo "- A patch is already upstream. Remove its file and toolchain build-definition reference in a separate reviewed PR targeting ${base_branch}; rerun maintenance to supersede this blocked PR."
            fi
        else
            echo "- State file: (none; update is complete)"
        fi
    } > "${output_file}"
}

function mark_unresolved_suffix_as_skipped() {
    local should_mark=0

    for patch in "${patch_files[@]}"
    do
        if [[ "${patch}" == "${failed_patch}" ]]
        then
            should_mark=1
            continue
        fi

        if [[ ${should_mark} -eq 1 && "${patch_phase_status[${patch}]:-pending}" != "applied" ]]
        then
            patch_phase_status["${patch}"]="skipped"
            patch_file_status["${patch}"]="not-updated"
            patch_resolution["${patch}"]="skipped"
        fi
    done
}

repo=$(get_config_value REPO)
tag=$(get_config_value TAG)
revision=$(get_config_value REVISION)
tag_pattern=$(get_config_value PATTERN)
tag_exclude=$(get_config_value EXCLUDE)

if [[ -z "${repo}" || -z "${tag}" || -z "${tag_pattern}" ]]
then
    echo "Could not read the toolchain configuration for tool '${tool_lc}'."
    exit 1
fi

known_remote=0
if update_is_known_reaveros_remote "${repo_root}"
then
    known_remote=1
else
    if [[ ${pr} -eq 1 ]]
    then
        echo "Refusing to publish to an unrecognized repository remote." >&2
        exit 1
    fi
fi

declare -a patch_files
declare -A patch_source_commit
declare -A patch_cherry_commit
declare -A patch_phase_status
declare -A patch_file_status
declare -A patch_resolution

declare -a updated_patches
declare -a unchanged_patches
declare -a unresolved_patches

old_tag=""
new_tag=""
old_revision=""
new_revision=""
new_source_digest=""
base_branch=""
update_branch=""
old_work_branch=""
new_work_branch=""
failed_patch=""

remote_tags=$(update_retry 3 git ls-remote --tags "${repo}")

if [[ ${continue_mode} -eq 1 ]]
then
    checkout_continue_update_branch
    read_state

    for patch in "${patch_files[@]}"
    do
        if [[ ${patch_resolution[${patch}]:-} == redundant ]]
        then
            echo "${patch} is already upstream; --continue cannot repair this PR. Remove the patch and its toolchain build-definition reference in a separate reviewed PR targeting ${base_branch}, then rerun maintenance." >&2
            exit 1
        fi
    done

    if [[ -z "${old_revision}" ]]
    then
        old_revision=$(get_tag_revision "${old_tag}")
    fi
    if [[ -z "${new_revision}" ]]
    then
        new_revision=$(get_tag_revision "${new_tag}")
    fi
else
    old_tag="${tag}"
    old_revision="${revision}"
    latest_tag=$(get_latest_tag)

    if [[ -z "${latest_tag}" ]]
    then
        echo "Could not determine latest tag for ${tool_lc}."
        exit 1
    fi

    if [[ -z "${old_revision}" ]]
    then
        echo "Could not read the pinned revision for '${tool_lc}'."
        exit 1
    fi

    current_remote_revision=$(get_tag_revision "${old_tag}")
    if [[ "${old_revision}" != "${current_remote_revision}" ]]
    then
        echo "Configured tag ${old_tag} resolves to ${current_remote_revision}, not ${old_revision}."
        exit 1
    fi

    new_revision=$(get_tag_revision "${latest_tag}")

    if [[ "${old_tag}" != "${latest_tag}" ]]
    then
        echo "${tool_lc}: upgrade available: ${old_tag} -> ${latest_tag}"
    else
        exit 0
    fi

    if [[ ${commit_mode} -eq 0 ]]
    then
        exit 0
    fi

    new_tag="${latest_tag}"
    if [[ "${tool_lc}" == "llvm" ]]
    then
        new_source_digest=$(get_llvm_source_digest "${new_tag}")
    fi
    base_branch="${starting_branch}"
    old_tag_branch=$(update_sanitize_branch_component "${old_tag}")
    new_tag_branch=$(update_sanitize_branch_component "${new_tag}")
    base_branch_component=$(update_sanitize_branch_component "${base_branch}")
    update_branch="maintenance/update/${tool_lc}/${base_branch_component}/${new_tag}"
    old_work_branch="reaveros-maintenance/${tool_lc}-${old_tag_branch}-patches"
    new_work_branch="reaveros-maintenance/${tool_lc}-${new_tag_branch}-cherry-picks"

    if [[ ${commit_mode} -eq 1 && ${pr} -eq 0 \
        && ${REAVEROS_MAINTENANCE_CI:-0} == 1 \
        && ${known_remote} -eq 1 ]]
    then
        existing_status=0
        update_existing_branch_is_current \
            "${repo_root}" "${update_branch}" "${base_branch}" \
            || existing_status=$?
        if [[ ${existing_status} -eq 0 ]]
        then
            echo "Current update PR already exists for ${tool_lc}; skipping."
            exit 0
        elif [[ ${existing_status} -ne 1 ]]
        then
            echo "Could not inspect the existing ${tool_lc} update." >&2
            exit 1
        fi
    fi

    list_patch_files

    for patch in "${patch_files[@]}"
    do
        patch_source_commit["${patch}"]=""
        patch_cherry_commit["${patch}"]=""
        patch_phase_status["${patch}"]="pending"
        patch_file_status["${patch}"]="not-updated"
        patch_resolution["${patch}"]="pending"
    done
fi

if [[ -z "${old_tag}" || -z "${new_tag}" \
      || -z "${old_revision}" || -z "${new_revision}" \
      || -z "${update_branch}" ]]
then
    echo "Update state is incomplete; refusing to proceed."
    exit 1
fi

if [[ "${tool_lc}" == "llvm" \
      && ! "${new_source_digest}" =~ ^[0-9a-f]{64}$ ]]
then
    echo "The LLVM update has no pinned release-archive digest." >&2
    exit 1
fi

if [[ ${commit_mode} -eq 1 ]]
then
    if [[ ${pr} -eq 1 && ${known_remote} -eq 1 && ${continue_mode} -eq 0 && ${amend_mode} -eq 0 ]] && update_remote_branch_exists "${repo_root}" "${update_branch}"
    then
        update_require_gh
        update_reconcile_existing_branch \
            "${repo_root}" \
            "${update_branch}" \
            "${base_branch}" \
            "maintenance/update-state/${tool_lc}.state"

        if [[ "${update_existing_branch_action}" == "skip" ]]
        then
            echo "Remote branch ${update_branch} already has an active resolved PR, skipping."
            exit 0
        fi

        if [[ "${update_existing_branch_action}" == "blocked" ]]
        then
            echo "Remote branch ${update_branch} has an active PR with failed checks."
            exit 1
        fi

        echo "Rebuilding ${update_branch} from ${base_branch}."
    fi

    ensure_update_branch_checked_out "${base_branch}"
fi

set_config_tag "${new_tag}"
set_config_revision "${new_revision}"
set_llvm_source_digest

ensure_checkout
if [[ ${reconstructed_checkout} -eq 1 ]]
then
    exit 1
fi

if [[ ${#patch_files[@]} -gt 0 ]]
then
    if [[ ${continue_mode} -eq 0 ]]
    then
        git -C "${checkout_dir}" checkout -B "${old_work_branch}" "${old_revision}"

        for patch in "${patch_files[@]}"
        do
            if ! git -C "${repo_root}" cat-file -e \
                "${base_branch}:${patch}" 2>/dev/null
            then
                echo "Baseline patch not found on ${base_branch}: ${patch}"
                exit 1
            fi

            if ! git -C "${checkout_dir}" apply \
                <(git -C "${repo_root}" show "${base_branch}:${patch}")
            then
                echo "Could not apply ${patch} to ${old_tag}."
                exit 1
            fi

            git -C "${checkout_dir}" add -A
            source_git commit --allow-empty -m "reaveros-maintenance: ${patch}" >/dev/null
            patch_source_commit["${patch}"]=$(git -C "${checkout_dir}" rev-parse HEAD)
            patch_phase_status["${patch}"]="pending"
            patch_file_status["${patch}"]="not-updated"
        done

        git -C "${checkout_dir}" checkout -B "${new_work_branch}" "${new_revision}"
    else
        if git -C "${checkout_dir}" show-ref --verify --quiet "refs/heads/${new_work_branch}"
        then
            git -C "${checkout_dir}" checkout "${new_work_branch}"
        else
            echo "Cannot continue: missing ${new_work_branch} in ${checkout_dir}."
            exit 1
        fi

        for patch in "${patch_files[@]}"
        do
            if [[ -z "${patch_source_commit[${patch}]}" ]]
            then
                echo "Cannot continue: missing source commit for ${patch} in state file."
                exit 1
            fi
        done
    fi

    if [[ -f "${checkout_dir}/.git/CHERRY_PICK_HEAD" ]]
    then
        if [[ -z "${failed_patch}" ]]
        then
            for patch in "${patch_files[@]}"
            do
                if [[ "${patch_phase_status[${patch}]:-pending}" != "applied" ]]
                then
                    failed_patch="${patch}"
                    break
                fi
            done
        fi

        if ! source_git cherry-pick --continue
        then
            echo "Cherry-pick is still unresolved for ${failed_patch}."
        else
            if [[ -n "${failed_patch}" ]]
            then
                patch_phase_status["${failed_patch}"]="applied"
                patch_cherry_commit["${failed_patch}"]=$(git -C "${checkout_dir}" rev-parse HEAD)
                patch_resolution["${failed_patch}"]="manual"
            fi
            failed_patch=""
        fi
    fi

    if [[ -n "${failed_patch}" && ! -f "${checkout_dir}/.git/CHERRY_PICK_HEAD" ]]
    then
        if [[ "${patch_phase_status[${failed_patch}]:-pending}" == "failed" ]]
        then
            source_commit="${patch_source_commit[${failed_patch}]:-}"
            source_subject=""
            head_subject=""
            tree_dirty=0

            if [[ -n "${source_commit}" ]]
            then
                source_subject=$(git -C "${checkout_dir}" show -s --format=%s "${source_commit}" 2>/dev/null || true)
            fi

            head_subject=$(git -C "${checkout_dir}" show -s --format=%s HEAD 2>/dev/null || true)

            if ! git -C "${checkout_dir}" diff --quiet || ! git -C "${checkout_dir}" diff --cached --quiet
            then
                tree_dirty=1
            fi

            if [[ -n "${source_subject}" && "${source_subject}" == "${head_subject}" ]]
            then
                patch_phase_status["${failed_patch}"]="applied"
                patch_cherry_commit["${failed_patch}"]=$(git -C "${checkout_dir}" rev-parse HEAD)
                patch_resolution["${failed_patch}"]="manual"
            elif [[ ${tree_dirty} -eq 1 ]]
            then
                if [[ -n "${source_commit}" ]]
                then
                    source_git commit --reuse-message "${source_commit}" >/dev/null
                else
                    source_git commit -m "reaveros-maintenance: ${failed_patch}" >/dev/null
                fi
                patch_phase_status["${failed_patch}"]="applied"
                patch_cherry_commit["${failed_patch}"]=$(git -C "${checkout_dir}" rev-parse HEAD)
                patch_resolution["${failed_patch}"]="manual"
            else
                patch_phase_status["${failed_patch}"]="pending"
            fi
        fi

        failed_patch=""
    fi

    if [[ -z "${failed_patch}" && ! -f "${checkout_dir}/.git/CHERRY_PICK_HEAD" ]]
    then
        for patch in "${patch_files[@]}"
        do
            if [[ "${patch_phase_status[${patch}]:-pending}" == "applied" ]]
            then
                continue
            fi

            cherry_pick_applied=0
            resolution_method="failed"
            if source_git cherry-pick --keep-redundant-commits "${patch_source_commit[${patch}]}"
            then
                cherry_pick_applied=1
                resolution_method="clean"
            elif [[ -n "${REAVEROS_COPILOT_PATCH_CONFLICT_RESOLVER:-}" ]]
            then
                echo "Trying the ${tool_lc} patch conflict resolver for ${patch}."
                resolver_status=0
                "${REAVEROS_COPILOT_PATCH_CONFLICT_RESOLVER}" \
                    "${tool_lc}" \
                    "${checkout_dir}" \
                    "${patch}" \
                    "${old_tag}" \
                    "${new_tag}" \
                    "${patch_source_commit[${patch}]}" \
                    || resolver_status=$?
                if [[ ${resolver_status} -eq 42 ]]
                then
                    echo "The patch resolver detected an unrelated mutation; refusing to publish this update." >&2
                    trap - EXIT
                    exit 1
                fi
                if [[ ${resolver_status} -eq 0 ]] \
                   && source_git cherry-pick --continue
                then
                    cherry_pick_applied=1
                    resolution_method="copilot"
                else
                    echo "The ${tool_lc} patch conflict resolver could not resolve ${patch}."
                fi
            fi

            if [[ ${cherry_pick_applied} -eq 0 ]]
            then
                failed_patch="${patch}"
                patch_phase_status["${patch}"]="failed"
                patch_file_status["${patch}"]="not-updated"
                patch_resolution["${patch}"]="failed"
                echo "Could not cherry-pick ${patch} onto ${new_tag}; stopping there."
                break
            fi

            cherry_commit=$(git -C "${checkout_dir}" rev-parse HEAD)
            if git -C "${checkout_dir}" diff --no-ext-diff --quiet \
                "${cherry_commit}^" "${cherry_commit}"
            then
                failed_patch="${patch}"
                patch_phase_status["${patch}"]="failed"
                patch_file_status["${patch}"]="not-updated"
                patch_resolution["${patch}"]="redundant"
                echo "${patch} is already in ${new_tag}; retaining it until a separate reviewed removal on ${base_branch}."
                break
            fi

            patch_phase_status["${patch}"]="applied"
            patch_cherry_commit["${patch}"]="${cherry_commit}"
            patch_resolution["${patch}"]="${resolution_method}"
        done
    fi

    if [[ -n "${failed_patch}" ]]
    then
        mark_unresolved_suffix_as_skipped
    fi

    for patch in "${patch_files[@]}"
    do
        if [[ "${patch_phase_status[${patch}]:-pending}" != "applied" ]]
        then
            patch_file_status["${patch}"]="not-updated"
            continue
        fi

        cherry_commit="${patch_cherry_commit[${patch}]}"
        patch_path="${repo_root}/${patch}"

        if [[ -z "${cherry_commit}" ]]
        then
            patch_phase_status["${patch}"]="pending"
            patch_file_status["${patch}"]="not-updated"
            patch_resolution["${patch}"]="pending"
            continue
        fi

        tmp_new_patch=$(mktemp)
        tmp_old_norm=$(mktemp)
        tmp_new_norm=$(mktemp)

        git -C "${checkout_dir}" diff --no-color --no-ext-diff "${cherry_commit}^" "${cherry_commit}" > "${tmp_new_patch}"

        if cmp -s "${patch_path}" "${tmp_new_patch}"
        then
            patch_file_status["${patch}"]="unchanged"
        else
            normalize_patch < "${patch_path}" > "${tmp_old_norm}"
            normalize_patch < "${tmp_new_patch}" > "${tmp_new_norm}"

            if cmp -s "${tmp_old_norm}" "${tmp_new_norm}"
            then
                patch_file_status["${patch}"]="unchanged"
            else
                cp "${tmp_new_patch}" "${patch_path}"
                patch_file_status["${patch}"]="updated"
            fi
        fi

        rm -f "${tmp_new_patch}" "${tmp_old_norm}" "${tmp_new_norm}"
    done
fi

write_state

git -C "${repo_root}" add "toolchain/config.cmake"
if [[ -f "${state_file}" ]] || git -C "${repo_root}" cat-file -e "HEAD:maintenance/update-state/${tool_lc}.state" 2>/dev/null
then
    git -C "${repo_root}" add -A "maintenance/update-state/${tool_lc}.state"
fi
for patch in "${patch_files[@]}"
do
    git -C "${repo_root}" add "${patch}"
done

allowed_staged_paths=(
    "toolchain/config.cmake"
    "maintenance/update-state/${tool_lc}.state"
)
allowed_staged_paths+=("${patch_files[@]}")
update_require_only_staged_paths "${repo_root}" "${allowed_staged_paths[@]}"

commit_message_path=$(update_make_temp_file "commit-message-${tool_lc}")
build_commit_message "${commit_message_path}"

if [[ ${amend_mode} -eq 1 ]]
then
    git -C "${repo_root}" -c commit.gpgsign=false commit --no-gpg-sign \
        --amend --file "${commit_message_path}"
else
    if git -C "${repo_root}" diff --cached --quiet
    then
        echo "No repository changes to commit for ${tool_lc}."
    else
        git -C "${repo_root}" -c commit.gpgsign=false commit --no-gpg-sign \
            --file "${commit_message_path}"
    fi
fi

rm -f "${commit_message_path}"
update_record_branch "${update_branch}"

if [[ ${pr} -eq 0 ]]
then
    if [[ ${#unresolved_patches[@]} -gt 0 ]]
    then
        echo "The ${tool_lc} update contains unresolved patches."
        exit 1
    fi
    exit 0
fi

if [[ ${known_remote} -eq 0 ]]
then
    if [[ ${#unresolved_patches[@]} -gt 0 ]]
    then
        echo "The ${tool_lc} update contains unresolved patches."
        exit 1
    fi
    exit 0
fi

update_require_gh
published_revision=$("${source_dir}/publish-signed-update" \
    "${repo_root}" "${update_branch}" "${base_branch}")

pr_title="Update toolchain tool ${tool_lc} from ${old_tag} to ${new_tag}."
pr_body_path=$(update_make_temp_file "pr-body-${tool_lc}")
build_pr_body "${pr_body_path}"
update_upsert_pr "${update_branch}" "${base_branch}" "${pr_title}" "${pr_body_path}"

rm -f "${pr_body_path}"

if [[ ${#unresolved_patches[@]} -gt 0 ]]
then
    pr_data=$(gh -R reaver-project/reaveros pr view "${update_pr_number}" --json labels)
    blocked_message="Automatic conflict resolution could not complete this patch refresh. This update will remain active and blocked until it is repaired manually or a newer update supersedes it."
    if has_redundant_patch
    then
        blocked_message="A patch is already upstream. Remove its file and toolchain build-definition reference in a separate reviewed PR targeting ${base_branch}, then rerun maintenance to supersede this blocked PR."
    fi
    update_mark_pr_blocked \
        "reaver-project/reaveros" \
        "${update_pr_number}" \
        "${pr_data}" \
        "${blocked_message}"
    echo "The ${tool_lc} update contains unresolved patches."
    exit 1
fi

update_enable_auto_merge "${update_pr_number}" "${published_revision}"
