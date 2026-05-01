#!/usr/bin/env bash
set -euo pipefail

REPO_SSH="${REPO_SSH:-git@github.com:USER/portfw.git}"
APP_DIR="${APP_DIR:-/opt/portfw}"
BRANCH="${BRANCH:-main}"

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root"
  exit 1
fi

apt-get update -y
apt-get install -y git

if [ -d "$APP_DIR/.git" ]; then
  cd "$APP_DIR"
  git fetch --all --prune
  git reset --hard "origin/$BRANCH"
else
  rm -rf "$APP_DIR"
  git clone -b "$BRANCH" "$REPO_SSH" "$APP_DIR"
fi

cd "$APP_DIR"
bash ./install.sh
systemctl daemon-reload
systemctl enable --now portfw.service
echo "Deploy complete"