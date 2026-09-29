#!/usr/bin/env bash

reaver_project_compiler_cache_args=()

reaver_project_compiler_cache_options()
{
    reaver_project_compiler_cache_args=()
    if [[ -z ${REAVER_PROJECT_SCCACHE_HOST_DIR:-} ]]
    then
        return
    fi

    local host_directory=${REAVER_PROJECT_SCCACHE_HOST_DIR}
    local container_directory=${REAVER_PROJECT_SCCACHE_CONTAINER_DIR:-}
    if [[ ${host_directory} != /* || ! -d ${host_directory} \
        || ! -x ${host_directory}/sccache \
        || ! -S ${host_directory}/sccache.sock \
        || ${container_directory} != /run/reaver-project/compiler-cache ]]
    then
        printf 'The host compiler-cache client or socket is unavailable.\n' >&2
        return 1
    fi

    reaver_project_compiler_cache_args=(
        --volume "${host_directory}:${container_directory}:ro"
        --env "REAVER_PROJECT_SCCACHE_CONTAINER_DIR=${container_directory}"
        --env "SCCACHE_SERVER_UDS=${container_directory}/sccache.sock"
        --env SCCACHE_CLIENT_SIDE=1
    )
}
