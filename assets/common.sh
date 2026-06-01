#!/bin/bash

set -e

TMPDIR=/tmp

registry=""
scope=""
yarn_args=""
use_jfrog_cli=0

cleanup_npmrc() {
    rm /home/node/.npmrc
}

setup_npmrc() {
    trap cleanup_npmrc EXIT

    mkdir -p /home/node/.npm
    chown -R node:node /home/node/.npm

    echo -n > /home/node/.npmrc
    chown node:node /home/node/.npmrc

    registry_target="${registry:-https://registry.npmjs.org/}"
    registry_target="//$(printf "%s" "${registry_target}" | sed -E 's#^https?://##')"

    if [ -n "${username}" ] && [ -n "${password}" ]; then
      jf c add --url "${registry}" --user "${username}" --password "${password}" --interactive=false
      jf npm-config --repo-resolve virtual-npm-release --repo-deploy local-ch-npm-release
      use_jfrog_cli=1
    elif [ -n "$token" ]; then
      echo "${registry_target}:_authToken=${token}" >> /home/node/.npmrc
    fi

    if [ -n "$scope" ]; then
        if [ -z "$registry" ]; then
          echo "  invalid payload (defined scope but missing registry)"
          exit 1
        fi

        echo "@${scope}:registry=${registry}" \
        >> /home/node/.npmrc

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
    scope=$(jq -r '.source.scope // ""' <<< "${payload}")
    package=$(jq -r '.source.package // ""' <<< "${payload}")

    echo "Initializing npmrc..."
    setup_npmrc
    setup_package
}

npm() {
    su node -c "npm $*"
}
