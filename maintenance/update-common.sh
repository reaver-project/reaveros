#!/usr/bin/env bash

function update_get_config_value() {
    local config_file="$1"
    local key="$2"
    local value

    value=$(sed -nE "s#^set\\(${key}[[:space:]]+([^)]*)\\)#\\1#p" "${config_file}" | head -n1)
    value="${value%\"}"
    value="${value#\"}"
    printf "%s" "${value}"
}

function update_is_known_reaveros_remote() {
    local repo_root="$1"
    local remote_push

    remote_push=$(git -C "${repo_root}" remote get-url --push origin 2>/dev/null || true)

    [[ "${remote_push}" == "git@github.com:reaver-project/reaveros.git" \
        || "${remote_push}" == "git@github.com:reaver-project/reaveros" \
        || "${remote_push}" == "https://github.com/reaver-project/reaveros" \
        || "${remote_push}" == "https://github.com/reaver-project/reaveros.git" ]]
}

function update_remote_branch_exists() {
    local repo_root="$1"
    local branch="$2"

    git -C "${repo_root}" ls-remote --exit-code --heads origin "${branch}" >/dev/null 2>&1
}

function update_existing_branch_is_current() {
    local repo_root="$1"
    local branch="$2"
    local base_branch="$3"
    local base_revision
    local remote_revision
    local status
    local pr_number

    base_revision=$(git -C "${repo_root}" rev-parse "${base_branch}") || return 2
    remote_revision=$(git -C "${repo_root}" ls-remote --heads origin \
        "refs/heads/${branch}" | cut -f1) || return 2
    if [[ -z ${remote_revision} ]]
    then
        return 1
    fi

    update_require_gh
    pr_number=$(gh -R reaver-project/reaveros pr list \
        --head "${branch}" --base "${base_branch}" --state open \
        --json number --jq '.[0].number // ""') || return 2
    if [[ -z ${pr_number} ]]
    then
        return 1
    fi

    status=$(gh api \
        "repos/reaver-project/reaveros/compare/${base_revision}...${remote_revision}" \
        --jq '.status') || return 2
    if [[ ${status} == ahead ]]
    then
        update_record_existing_branch "${branch}"
        return 0
    fi
    return 1
}

function update_record_branch() {
    local branch="$1"
    if [[ -n ${GITHUB_OUTPUT:-} ]]
    then
        printf 'branch=%s\n' "${branch}" >> "${GITHUB_OUTPUT}"
    fi
}

function update_record_existing_branch() {
    local branch="$1"
    if [[ -n ${GITHUB_OUTPUT:-} ]]
    then
        printf 'existing_branch=%s\n' "${branch}" >> "${GITHUB_OUTPUT}"
    fi
}

function update_require_gh() {
    if ! command -v gh >/dev/null 2>&1
    then
        echo "gh CLI is required for --pr, but was not found in PATH."
        exit 1
    fi
}

function update_make_temp_file() {
    local name="$1"
    mktemp "/tmp/reaveros-update-${name}.XXXXXX"
}

function update_sanitize_branch_component() {
    local value="$1"
    value=${value//[^A-Za-z0-9._-]/-}
    printf '%s' "${value}"
}

function update_retry() {
    local max_attempts="$1"
    shift

    local attempt=1
    until "$@"
    do
        if [[ ${attempt} -ge ${max_attempts} ]]
        then
            return 1
        fi

        echo "Attempt ${attempt} failed; retrying." >&2
        sleep "${attempt}"
        attempt=$((attempt + 1))
    done
}

function update_require_clean_worktree() {
    local repo_root="$1"

    if ! git -C "${repo_root}" diff --quiet --ignore-submodules -- \
       || ! git -C "${repo_root}" diff --cached --quiet --ignore-submodules --
    then
        echo "Tracked worktree and index changes must be committed or stashed before creating a tool update."
        return 1
    fi
}

function update_require_only_staged_paths() {
    local repo_root="$1"
    shift

    declare -A allowed_paths=()
    local path
    for path in "$@"
    do
        allowed_paths["${path}"]=1
    done

    declare -a staged_paths
    mapfile -d '' -t staged_paths < <(
        git -C "${repo_root}" diff --cached --name-only -z
    )

    for path in "${staged_paths[@]}"
    do
        if [[ -z "${allowed_paths[${path}]+x}" ]]
        then
            echo "Refusing to include an unrelated staged path in the tool update: ${path}"
            return 1
        fi
    done
}

function update_close_superseded_prs() {
    local branch="$1"
    local base_branch="$2"
    local repo_slug="reaver-project/reaveros"
    local branch_suffix
    local tool
    local branch_prefix
    local base_component
    local pr_list
    local pr_number
    local pr_branch
    local open_pr

    branch_suffix=${branch#maintenance/update/}
    if [[ "${branch_suffix}" == "${branch}" || "${branch_suffix}" != */* ]]
    then
        echo "Cannot determine the tool from update branch '${branch}'."
        return 1
    fi

    tool=${branch_suffix%%/*}
    branch_prefix="maintenance/update/${tool}/"
    base_component=$(update_sanitize_branch_component "${base_branch}")

    gh -R "${repo_slug}" label create "automatic: toolchain tool update" \
        --color C2E0C6 \
        --description "Automated update to a toolchain tool." \
        --force > /dev/null || return 1

    pr_list=$(gh -R "${repo_slug}" pr list \
        --base "${base_branch}" \
        --state open \
        --label "automatic: toolchain tool update" \
        --limit 1000 \
        --json number,headRefName \
        --jq '.[] | [.number, .headRefName] | @tsv') || return 1

    while IFS=$'\t' read -r pr_number pr_branch
    do
        if [[ -z "${pr_number}" || "${pr_branch}" == "${branch}" ]]
        then
            continue
        fi

        if [[ "${pr_branch}" == "${branch_prefix}"* ]]
        then
            gh -R "${repo_slug}" pr close "${pr_number}" \
                --delete-branch \
                --comment "Superseded by the automatic toolchain tool update on branch \`${branch}\`." \
                || return 1
        fi
    done <<< "${pr_list}"

    local generated_branch
    local generated_suffix
    local same_target_prefix="${branch_prefix}${base_component}/"
    local branch_list

    branch_list=$(gh api --paginate \
        "repos/${repo_slug}/branches?per_page=100" \
        --jq '.[].name') || return 1

    while IFS= read -r generated_branch
    do
        if [[ -z "${generated_branch}" || "${generated_branch}" == "${branch}" ]]
        then
            continue
        fi

        if [[ "${generated_branch}" != "${branch_prefix}"* ]]
        then
            continue
        fi

        generated_suffix=${generated_branch#${branch_prefix}}
        if [[ "${generated_branch}" == "${same_target_prefix}"* ]]
        then
            :
        elif [[ "${base_branch}" == "main" && "${generated_suffix}" != */* ]]
        then
            :
        else
            continue
        fi

        open_pr=$(gh -R "${repo_slug}" pr list \
            --head "${generated_branch}" \
            --state open \
            --json number \
            --jq '.[0].number // ""') || return 1
        if [[ -n "${open_pr}" ]]
        then
            continue
        fi

        gh api \
            --method DELETE \
            "repos/${repo_slug}/git/refs/heads/${generated_branch}" \
            || return 1
    done <<< "${branch_list}"
}

function update_mark_pr_blocked() {
    local repo_slug="$1"
    local pr_number="$2"
    local pr_data="$3"
    local message="$4"

    if jq -e '.labels | any(.name == "automatic: blocked")' \
        <<< "${pr_data}" >/dev/null
    then
        return 0
    fi

    gh -R "${repo_slug}" label create "automatic: blocked" \
        --color B60205 \
        --description "Automatic maintenance requires intervention." \
        --force || return 1
    gh -R "${repo_slug}" pr edit "${pr_number}" \
        --add-label "automatic: blocked" || return 1
    gh -R "${repo_slug}" pr comment "${pr_number}" \
        --body "${message}" || return 1
}

function update_verified_maintenance_head() {
    local repo_slug="$1"
    local head_oid="$2"
    local base_oid="$3"
    local app_slug=${REAVEROS_MAINTENANCE_APP_SLUG:-}
    local commit_data

    if [[ ! ${head_oid} =~ ^[0-9a-f]{40}$ \
        || ! ${base_oid} =~ ^[0-9a-f]{40}$ \
        || ! ${app_slug} =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]
    then
        return 1
    fi

    commit_data=$(gh api "repos/${repo_slug}/commits/${head_oid}") || return 1
    jq --exit-status \
        --arg head "${head_oid}" \
        --arg base "${base_oid}" \
        --arg actor "${app_slug}[bot]" \
        '.sha == $head
         and .author.login == $actor
         and .commit.verification.verified == true
         and (.parents | length) == 1
         and .parents[0].sha == $base' \
        <<< "${commit_data}" > /dev/null
}

function update_reconcile_existing_branch() {
    local repo_root="$1"
    local branch="$2"
    local base_branch="$3"
    local unresolved_state_path="${4:-}"
    local repo_slug="reaver-project/reaveros"
    local pr_number
    local pr_data
    local pr_base_oid
    local pr_head_oid
    local compare_status
    local check_state
    local is_blocked
    local rebuild_reason=""

    update_existing_branch_action="skip"

    update_close_superseded_prs "${branch}" "${base_branch}" || return 1

    pr_number=$(gh -R "${repo_slug}" pr list \
        --head "${branch}" \
        --base "${base_branch}" \
        --state open \
        --json number \
        --jq '.[0].number // ""') || return 1

    if [[ -n "${pr_number}" ]]
    then
        pr_data=$(gh -R "${repo_slug}" pr view "${pr_number}" \
            --json files,baseRefOid,headRefOid,statusCheckRollup,labels,autoMergeRequest) || return 1

        if [[ -n "${unresolved_state_path}" ]] \
           && jq -e --arg path "${unresolved_state_path}" \
                '.files | any(.path == $path)' <<< "${pr_data}" >/dev/null
        then
            update_mark_pr_blocked \
                "${repo_slug}" \
                "${pr_number}" \
                "${pr_data}" \
                "Automatic conflict resolution could not complete this patch refresh. This update will remain active and blocked until it is repaired manually or a newer update supersedes it." \
                || return 1
            update_existing_branch_action="blocked"
            return 0
        else
            pr_base_oid=$(jq -r '.baseRefOid' <<< "${pr_data}")
            pr_head_oid=$(jq -r '.headRefOid' <<< "${pr_data}")
            compare_status=$(gh api \
                "repos/${repo_slug}/compare/${pr_base_oid}...${pr_head_oid}" \
                --jq '.status') || return 1

            if [[ "${compare_status}" == "ahead" ]]
            then
                if ! update_verified_maintenance_head \
                    "${repo_slug}" "${pr_head_oid}" "${pr_base_oid}"
                then
                    update_mark_pr_blocked \
                        "${repo_slug}" \
                        "${pr_number}" \
                        "${pr_data}" \
                        "The automatic update head is not a verified Maintenance App commit directly on the current base; manual review is required." \
                        || return 1
                    update_existing_branch_action="blocked"
                    return 0
                fi
                check_state=$(jq -r '
                    [.statusCheckRollup[]? |
                        if .__typename == "CheckRun" then
                            if .status != "COMPLETED" then
                                "pending"
                            elif .conclusion == "SUCCESS"
                                or .conclusion == "NEUTRAL"
                                or .conclusion == "SKIPPED" then
                                "success"
                            else
                                "failed"
                            end
                        else
                            if .state == "SUCCESS" then
                                "success"
                            elif .state == "PENDING" or .state == "EXPECTED" then
                                "pending"
                            else
                                "failed"
                            end
                        end
                    ] as $states |
                    if any($states[]; . == "failed") then
                        "failed"
                    elif any($states[]; . == "pending") then
                        "pending"
                    elif ($states | length) == 0 then
                        "none"
                    else
                        "success"
                    end
                ' <<< "${pr_data}") || return 1
                is_blocked=$(jq -r \
                    '.labels | any(.name == "automatic: blocked")' \
                    <<< "${pr_data}") || return 1

                if [[ "${check_state}" == "failed" ]]
                then
                    update_mark_pr_blocked \
                        "${repo_slug}" \
                        "${pr_number}" \
                        "${pr_data}" \
                        "Automatic maintenance found failed CI checks. This update will remain active and blocked until its checks pass or a newer update supersedes it." \
                        || return 1

                    update_existing_branch_action="blocked"
                    return 0
                fi

                if [[ "${check_state}" == "success" && "${is_blocked}" == "true" ]]
                then
                    gh -R "${repo_slug}" pr edit "${pr_number}" \
                        --remove-label "automatic: blocked" || return 1
                fi
                if [[ "${check_state}" == "success" ]] \
                   && jq -e '.autoMergeRequest == null' \
                        <<< "${pr_data}" > /dev/null
                then
                    update_enable_auto_merge "${pr_number}" "${pr_head_oid}" || return 1
                fi

                return 0
            fi

            rebuild_reason="${base_branch} advanced after the update branch was created"
        fi

        gh -R "${repo_slug}" pr close "${pr_number}" \
            --delete-branch \
            --comment "Restarting this update from ${base_branch} because ${rebuild_reason}." \
            || return 1
    else
        git -C "${repo_root}" push origin --delete "${branch}" || return 1
    fi

    if git -C "${repo_root}" show-ref --verify --quiet "refs/heads/${branch}"
    then
        git -C "${repo_root}" branch -D "${branch}" || return 1
    fi

    update_existing_branch_action="rebuild"
}

function update_upsert_pr() {
    local branch="$1"
    local base_branch="$2"
    local pr_title="$3"
    local pr_body_file="$4"
    local repo_slug="reaver-project/reaveros"
    local pr_number

    update_pr_number=""

    update_close_superseded_prs "${branch}" "${base_branch}"

    pr_number=$(gh -R "${repo_slug}" pr list \
        --head "${branch}" \
        --base "${base_branch}" \
        --state open \
        --json number \
        --jq '.[0].number // ""')

    if [[ -n "${pr_number}" ]]
    then
        gh -R "${repo_slug}" pr edit "${pr_number}" \
            --title "${pr_title}" \
            --body-file "${pr_body_file}" \
            --add-label "automatic: toolchain tool update"
    else
        gh -R "${repo_slug}" pr create \
            --head "${branch}" \
            --base "${base_branch}" \
            --title "${pr_title}" \
            --body-file "${pr_body_file}" \
            --label "automatic: toolchain tool update"

        pr_number=$(gh -R "${repo_slug}" pr list \
            --head "${branch}" \
            --base "${base_branch}" \
            --state open \
            --json number \
            --jq '.[0].number // ""')
    fi

    if [[ -z "${pr_number}" ]]
    then
        echo "Could not determine the pull request for ${branch}."
        return 1
    fi

    update_pr_number="${pr_number}"

    update_close_superseded_prs "${branch}" "${base_branch}"
}

function update_enable_auto_merge() {
    local pr_number="$1"
    local head_revision="$2"

    gh -R reaver-project/reaveros pr merge "${pr_number}" \
        --auto \
        --squash \
        --delete-branch \
        --match-head-commit "${head_revision}"
}
