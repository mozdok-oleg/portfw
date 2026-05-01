#!/usr/bin/env bash
set -euo pipefail

REPO_SSH="${REPO_SSH:-git@github.com:mozdok-oleg/portfw.git}"
APP_DIR="${APP_DIR:-/opt/portfw}"
BRANCH="${BRANCH:-main}"
SSH_KEY="/root/.ssh/portfw_deploy"

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root"
  exit 1
fi

apt-get update -y
apt-get install -y git

if [ -d "$APP_DIR/.git" ]; then
  cd "$APP_DIR"
  GIT_SSH_COMMAND="ssh -i ${SSH_KEY} -o IdentitiesOnly=yes" git fetch --all --prune
  GIT_SSH_COMMAND="ssh -i ${SSH_KEY} -o IdentitiesOnly=yes" git reset --hard "origin/$BRANCH"
else
  rm -rf "$APP_DIR"
  GIT_SSH_COMMAND="ssh -i ${SSH_KEY} -o IdentitiesOnly=yes" git clone -b "$BRANCH" "$REPO_SSH" "$APP_DIR"
fi

cd "$APP_DIR"
bash ./install.sh
systemctl daemon-reload
systemctl enable --now portfw.service
echo "Deploy complete"
