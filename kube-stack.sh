#!/usr/bin/env bash
# Kubernetes local stack: Docker + kubectl + Minikube for Debian 11/12
set -euo pipefail

# ===== Config (adjust as needed) =====
MINIKUBE_VERSION="latest"  # e.g. v1.34.0 or "latest"
KUBECTL_VERSION="latest"   # e.g. v1.30.2 or "latest"
DOCKER_CHANNEL="stable"    # stable/test
# ====================================

bold(){ echo -e "\033[1m$*\033[0m"; }
yellow(){ echo -e "\033[33m$*\033[0m"; }
red(){ echo -e "\033[31m$*\033[0m"; }
green(){ echo -e "\033[32m$*\033[0m"; }

need_root(){ if [[ ${EUID:-$(id -u)} -ne 0 ]]; then red "Run as root (sudo)."; exit 1; fi; }
detect_debian(){ . /etc/os-release || { red "Cannot detect OS"; exit 1; }; [[ "$ID" != "debian" ]] && yellow "Detected: $PRETTY_NAME (script tuned for Debian)"; echo "${VERSION_CODENAME:-bookworm}"; }

install_basics(){
  bold "Installing base packages..."
  apt-get update -y
  apt-get install -y --no-install-recommends \
    ca-certificates curl wget gnupg lsb-release apt-transport-https \
    software-properties-common jq bash-completion \
    conntrack iptables arptables ebtables ethtool socat uidmap
}

install_docker(){
  bold "Installing Docker..."
  if ! command -v docker >/dev/null; then
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    local codename="$1"
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian ${codename} ${DOCKER_CHANNEL}" \
      > /etc/apt/sources.list.d/docker.list
    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    systemctl enable --now docker
  else
    yellow "Docker already installed."
  fi

  # systemd cgroup driver improves k8s compatibility
  mkdir -p /etc/docker
  cat >/etc/docker/daemon.json <<'JSON'
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": { "max-size": "100m" },
  "storage-driver": "overlay2"
}
JSON
  systemctl restart docker || true

  # Add invoking user to docker group (requires re-login)
  local target_user="${SUDO_USER:-$USER}"
  if ! id -nG "$target_user" | grep -qw docker; then
    usermod -aG docker "$target_user" || true
    yellow "Added '$target_user' to docker group (re-login required)."
  fi
}

install_kubectl(){
  bold "Installing kubectl..."
  local ver="$KUBECTL_VERSION"
  [[ "$ver" == "latest" ]] && ver="$(curl -sL https://dl.k8s.io/release/stable.txt)"
  curl -sL "https://dl.k8s.io/release/${ver}/bin/linux/amd64/kubectl" -o /usr/local/bin/kubectl
  chmod +x /usr/local/bin/kubectl
  if ! grep -q "__start_kubectl" /etc/bash.bashrc; then
    {
      echo; echo "# kubectl completion"
      echo "source <(kubectl completion bash)"
      echo "alias k=kubectl"; echo "complete -F __start_kubectl k"
    } >> /etc/bash.bashrc
  fi
}

install_minikube(){
  bold "Installing Minikube..."
  local url
  if [[ "$MINIKUBE_VERSION" == "latest" ]]; then
    url="https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64"
  else
    url="https://storage.googleapis.com/minikube/releases/${MINIKUBE_VERSION}/minikube-linux-amd64"
  fi
  curl -sL "$url" -o /usr/local/bin/minikube
  chmod +x /usr/local/bin/minikube
}

post_notes(){
cat <<'EOF'

-------------------------------------------------
✅ Kube stack ready

Next steps:
1) Refresh groups (or log out/in):
   newgrp docker

2) Start Minikube (Docker driver):
   minikube start --driver=docker --kubernetes-version=stable
   # Example resources:
   # minikube start --driver=docker --cpus=4 --memory=6g --disk-size=30g

3) Verify:
   kubectl get nodes
   kubectl get pods -A

4) Dashboard:
   minikube addons enable dashboard
   minikube dashboard
-------------------------------------------------
EOF
}

maybe_start(){
  if [[ "${1-}" == "--start" ]]; then
    bold "Starting Minikube as non-root..."
    local target_user="${SUDO_USER:-$USER}"
    su - "$target_user" -c "minikube start --driver=docker --kubernetes-version=stable"
    su - "$target_user" -c "kubectl get nodes"
  fi
}

main(){
  need_root
  CODENAME="$(detect_debian)"
  install_basics
  install_docker "$CODENAME"
  install_kubectl
  install_minikube
  post_notes
  maybe_start "${1-}"
  green "All done (kube-stack)."
}

main "$@"
