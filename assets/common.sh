#!/bin/bash

set -e

TMPDIR=/tmp

registry=""
scope=""
yarn_args=""

cleanup_npmrc() {
    rm "${HOME}/.npmrc"
}

setup_npmrc() {
    trap cleanup_npmrc EXIT
    echo -n > "${HOME}/.npmrc"

    registry_target="${registry:-https://registry.npmjs.org/}"
    registry_target="//$(printf "%s" "${registry_target}" | sed -E 's#^https?://##')"

    if [ -n "${username}" ] && [ -n "${password}" ]; then
      encoded_password=$(printf "%s" "${password}" | base64 | tr -d '\n')
      echo "${registry_target}:username=${username}" >> "${HOME}/.npmrc"
      echo "${registry_target}:_password=${encoded_password}" >> "${HOME}/.npmrc"
      [ -n "$email" ] && echo "${registry_target}:email=${email}" >> "${HOME}/.npmrc"
    elif [ -n "$token" ]; then
      echo "${registry_target}:_authToken=${token}" >> "${HOME}/.npmrc"
    fi

    if [ -n "$scope" ]; then
        if [ -z "$registry" ]; then
          echo "  invalid payload (defined scope but missing registry)"
          exit 1
        fi

        echo "@${scope}:registry=${registry}" \
        >> "${HOME}/.npmrc"

        echo "  Scope limited to @$scope"
    fi

    if [ -n "$registry" ]; then
        echo "  Registry is ${registry}"
        if [ -z "${scope}" ]; then
            npm config set registry "${registry}"
            echo "  Registry change is global"
        fi
    fi
}

setup_package() {
    if [ -z "$package" ]; then
      echo "invalid payload (missing package)"
      exit 1
    fi
}

setup_resource() {
    registry=$(jq -r '.source.registry.uri // ""' <<< "${payload}")
    token=$(jq -r '.source.registry.token // ""' <<< "${payload}")
    username=$(jq -r '.source.registry.username // ""' <<< "${payload}")
    password=$(jq -r '.source.registry.password // ""' <<< "${payload}")
    email=$(jq -r '.source.registry.email // ""' <<< "${payload}")
    scope=$(jq -r '.source.scope // ""' <<< "${payload}")
    package=$(jq -r '.source.package // ""' <<< "${payload}")

    echo "Initializing npmrc..."
    setup_npmrc
    setup_package
}
