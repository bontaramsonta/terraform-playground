#!/bin/bash
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y git curl unzip jq ripgrep build-essential

mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o /etc/apt/keyrings/githubcli-archive-keyring.gpg
chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" >/etc/apt/sources.list.d/github-cli.list
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" >/etc/apt/sources.list.d/docker.list
apt-get update
apt-get install -y gh docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
usermod -aG docker ubuntu
systemctl enable --now docker containerd

hostnamectl set-hostname --pretty "t3code-box"
loginctl enable-linger ubuntu

sudo -iu ubuntu bash -c 'curl -fsSL https://t3.codes/install.sh | sh'
sudo -iu ubuntu bash -c 'curl -fsSL https://claude.ai/install.sh | bash'
sudo -iu ubuntu bash -c 'curl -fsSL https://vite.plus -o /tmp/vp-install.sh && VP_NODE_MANAGER=yes bash /tmp/vp-install.sh </dev/null'
sudo -iu ubuntu bash -c '. "$HOME/.config/vite-plus/env" && cd /tmp && vp env default node@24 && vp env default bun@1.4.4'

/home/ubuntu/.local/bin/t3 browser setup

touch /var/lib/t3code-box-ready
