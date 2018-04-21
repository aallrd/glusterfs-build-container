#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

function __usage_main() {
  echo "${0##*/}:"
  echo "-h|--help    : Print the helper."
  echo "--only-amd64 : Only build the amd64 docker image."
  echo "--only-arm   : Only build the arm docker image."
  return 0
}

function __main() {
  # Default behavior
  __target_archs=("x86_64" "arm")
  __docker_archs=("amd64" "arm32v7")
  __qemu_version="v2.11.0"
  __docker_repo="aallrd"
  __docker_image="glusterfs-build-container"
  __docker_tag="${__docker_repo}/${__docker_image}"

  # Parsing input parameters
  __parse_args "${@}"

  # Login on docker hub
  if [[ ${DOCKER_USERNAME:-} == "" || ${DOCKER_PASSWORD:-} == "" ]] ; then
    echo "DOCKER_USERNAME and/or DOCKER_PASSWORD are not set in this shell, cannot login on the Docker Hub."
    return 1
  else
    echo "${DOCKER_PASSWORD}" | docker login -u "${DOCKER_USERNAME}" --password-stdin
  fi

  # Registering handlers
  if [[ "$(uname -m)" == "x86_64" ]] ; then
    docker run --rm --privileged multiarch/qemu-user-static:register || true
  fi

  # Getting handlers
  for target_arch in ${__target_archs[@]}; do
    echo "Downloading qemu ${__qemu_version} static handler: x86_64_qemu-${target_arch}-static"
    wget -N "https://github.com/multiarch/qemu-user-static/releases/download/${__qemu_version}/x86_64_qemu-${target_arch}-static.tar.gz"
    tar -xzf "x86_64_qemu-${target_arch}-static.tar.gz"
  done

  # Building the docker images
  for docker_arch in ${__docker_archs[@]}; do
    case ${docker_arch} in
      amd64   ) qemu_arch="x86_64" ;;
      arm32v7 ) qemu_arch="arm" ;;
    esac
    echo "Building Dockerfile.${docker_arch}"
    docker build -f Dockerfile.${docker_arch} -t ${__docker_tag}:${docker_arch}-latest .
    echo "Pushing image ${__docker_tag}:${docker_arch}-latest"
    docker push ${__docker_tag}:${docker_arch}-latest
  done

  # Creating the manifest
  if [[ $(docker version | grep Version: | tail -n1 | awk '{print $2}' | awk -F'.' '{print $1}') -ge 18 ]] ; then
    # Need to enable experimental mode to access the manifest command
    if [[ -e "${HOME}/.docker/config.json" ]] ; then
        cp "${HOME}/.docker/config.json" "${HOME}/.docker/config.json.original"
        jq '. += { "experimental" : "enabled" }' < "${HOME}/.docker/config.json" > "${HOME}/.docker/config.json.new"
        mv "${HOME}/.docker/config.json.new" "${HOME}/.docker/config.json"
    else
        echo '{ "experimental" : "enabled" }' > "${HOME}/.docker/config.json"
        touch "${HOME}/.docker/config.json.rm"
    fi
    docker manifest create aallrd/glusterfs-build-container:latest aallrd/glusterfs-build-container:amd64-latest aallrd/glusterfs-build-container:arm32v7-latest || true
    docker manifest annotate aallrd/glusterfs-build-container:latest aallrd/glusterfs-build-container:arm32v7-latest --os linux --arch arm || true
    docker manifest aallrd/glusterfs-build-container:latest || true
    if [[ -e "${HOME}/.docker/config.json.original" ]] ; then
        mv "${HOME}/.docker/config.json.original" "${HOME}/.docker/config.json"
    elif [[ -e "${HOME}/.docker/config.json.rm" ]] ; then
        rm "${HOME}/.docker/config.json" "${HOME}/.docker/config.json.rm"
    fi
  else
    echo "The docker manifest command was introduced in the release 18.02."
  fi

  return 0
}

function __parse_args() {
  for arg in "${@}" ; do
      case "${arg}" in
          -h|--help)
              __usage_main
              exit 0
              ;;
          --only-amd64)
              __target_archs=("x86_64")
              __docker_archs=("amd64")
              ;;
          --only-arm)
              __target_archs=("arm")
              __docker_archs=("arm32v7")
              ;;
          *) _parsed_args=("${_parsed_args[@]:-} ${arg}")
      esac
  done
  return 0
}

__main "${@:-}"
