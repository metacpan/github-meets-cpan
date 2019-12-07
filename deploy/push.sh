#!/bin/bash

DEPLOY_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

if [[ "x${DEPLOY_REPO_SLUG}" != "x${TRAVIS_REPO_SLUG}" ]]; then
	echo "skip push.sh: only deploy on ${DEPLOY_REPO_SLUG} repo.";
	exit;
fi

if [[ "x$DOCKER_HUB_USER" == "x" ]]; then
	echo "DOCKER_HUB_USER env is not defined.";
	exit 1;
fi

if [[ "x$DOCKER_HUB_PASSWD" == "x" ]]; then
	echo "DOCKER_HUB_PASSWD env is not defined.";
	exit 1;
fi

source "${DEPLOY_DIR}/vars.sh"

cd "${DEPLOY_DIR}/.."

docker login -u "$DOCKER_HUB_USER" -p "$DOCKER_HUB_PASSWD"
docker push "$DOCKER_HUB_NAME"