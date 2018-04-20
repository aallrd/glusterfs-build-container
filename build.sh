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

  # Registering handlers
  docker run --rm --privileged multiarch/qemu-user-static:register || true

  # Getting handlers
  for target_arch in ${__target_archs[@]}; do
    echo "Downloading qemu ${__qemu_version} static handler: x86_64_qemu-${target_arch}-static"
    wget -N "https://github.com/multiarch/qemu-user-static/releases/download/${__qemu_version}/x86_64_qemu-${target_arch}-static.tar.gz"
    tar -xzf "x86_64_qemu-${target_arch}-static.tar.gz"
  done

  # Login on docker hub
  if [[ ${DOCKER_USERNAME:-} == "" || ${DOCKER_PASSWORD:-} == "" ]] ; then
    echo "DOCKER_USERNAME and/or DOCKER_PASSWORD are not set in this shell, cannot login on the Docker Hub."
    return 1
  else
    echo "${DOCKER_PASSWORD}" | docker login -u "${DOCKER_USERNAME}" --password-stdin
  fi
  
  # Building the docker images
  for docker_arch in ${__docker_archs[@]}; do
    case ${docker_arch} in
      amd64   ) qemu_arch="x86_64" ;;
      arm32v7 ) qemu_arch="arm" ;;
    esac
    echo "Configuring Dockerfile (${docker_arch}) with qemu (${qemu_arch})"
    cp Dockerfile.cross Dockerfile.${docker_arch}
    sed -i "s|__BASEIMAGE_ARCH__|${docker_arch}|g" Dockerfile.${docker_arch}
    sed -i "s|__QEMU_ARCH__|${qemu_arch}|g" Dockerfile.${docker_arch}
    if [ ${docker_arch} == 'amd64' ]; then
      sed -i "/__CROSS_/d" Dockerfile.${docker_arch}
    else
      sed -i "s/__CROSS_//g" Dockerfile.${docker_arch}
    fi
    echo "Building Dockerfile.${docker_arch}"
    docker build -f Dockerfile.${docker_arch} -t ${__docker_tag}:${docker_arch}-latest .
    echo "Pushing image ${__docker_tag}:${docker_arch}-latest"
    docker push ${__docker_tag}:${docker_arch}-latest
  done

  # Creating the manifest
  if [[ $(docker version | grep Version: | tail -n1 | awk '{print $2}' | awk -F'.' '{print $1}') -ge 18 ]] ; then
    docker manifest create aallrd/glusterfs-build-container:latest aallrd/glusterfs-build-container:amd64-latest aallrd/glusterfs-build-container:arm32v7-latest
    docker manifest annotate aallrd/glusterfs-build-container:latest aallrd/glusterfs-build-container:arm32v7-latest --os linux --arch arm
    docker manifest aallrd/glusterfs-build-container:latest
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

__main "${@}"
