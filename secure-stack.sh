#!/usr/bin/env bash
# Secure stack: OpenSSH (hardened) + Webmin + Fail2ban + UFW for Debian 11/12
set -euo pipefail

# ===== Config (adjust as needed) =====
SSH_PORT="22"                    # e.g. 2222
DISABLE_SSH_PASSWORD="no"        # yes = key-only login
ALLOW_SSH_USERS=""               # e.g. "user1 user2" (empty = allow all system users)
ENABLE_WEBMIN="yes"              # yes/no
ENABLE_FAIL2BAN="yes"            # yes/no
UFW_ALLOW_PORTS="22,80,443,10000" # Allowed inbound TCP ports
# ====================================

bold(){ echo -e "\033[1m$*\033[0m"; }
yellow(){ echo -e "\033[33m$*\033[0m"; }
red(){ echo -e "\033[31m$*\033[0m"; }
green(){ echo -e "\033[32m$*\033[0m"; }

need_root(){ if [[ ${EUID:-$(id -u)} -ne 0 ]]; then red "Run as root (sudo)."; exit 1; fi; }
detect_debian(){ . /etc/os-release || { red "Cannot detect OS"; exit 1; }; [[ "$ID" != "debian" ]] && yellow "Detected: $PRETTY_NAME (script tuned for Debian)"; }

install_openssh(){
  bold "Installing OpenSSH + hardening..."
  apt-get update -y
  apt-get install -y openssh-server
  systemctl enable --now ssh

  mkdir -p /etc/ssh/sshd_config.d
  cat >/etc/ssh/sshd_config.d/99-hardening.conf <<EOF
# ---- Managed by secure-stack.sh ----
Port ${SSH_PORT}
Protocol 2
PermitRootLogin no
PasswordAuthentication $( [[ "$DISABLE_SSH_PASSWORD" == "yes" ]] && echo "no" || echo "yes" )
PubkeyAuthentication yes
ChallengeResponseAuthentication no
UsePAM yes
X11Forwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
LoginGraceTime 30
MaxAuthTries 3
AllowTcpForwarding no
AllowAgentForwarding no
$( [[ -n "$ALLOW_SSH_USERS" ]] && echo "AllowUsers ${ALLOW_SSH_USERS}" || true )
EOF

  if [[ "$DISABLE_SSH_PASSWORD" == "yes" ]]; then
    yellow "PasswordAuthentication is DISABLED. Ensure your SSH public key is in ~/.ssh/authorized_keys."
  fi

  sshd -t
  systemctl restart ssh
}

install_webmin(){
  [[ "$ENABLE_WEBMIN" != "yes" ]] && { yellow "Skipping Webmin."; return; }
  bold "Installing Webmin..."
  apt-get install -y perl libnet-ssleay-perl openssl libauthen-pam-perl libpam-runtime libio-pty-perl unzip
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL http://www.webmin.com/jcameron-key.asc | gpg --dearmor -o /etc/apt/keyrings/webmin.gpg
  echo "deb [signed-by=/etc/apt/keyrings/webmin.gpg] http://download.webmin.com/download/repository sarge contrib" \
    > /etc/apt/sources.list.d/webmin.list
  apt-get update -y
  apt-get install -y webmin
  systemctl enable --now webmin || true
  green "Webmin → https://<server-ip>:10000"
}

install_fail2ban(){
  [[ "$ENABLE_FAIL2BAN" != "yes" ]] && { yellow "Skipping Fail2ban."; return; }
  bold "Installing Fail2ban..."
  apt-get install -y fail2ban
  systemctl enable --now fail2ban
  if [[ ! -f /etc/fail2ban/jail.local ]]; then
    cat >/etc/fail2ban/jail.local <<EOF
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5

[sshd]
enabled = true
port = ${SSH_PORT}
EOF
  fi
  systemctl restart fail2ban
}

setup_ufw(){
  bold "Configuring UFW..."
  apt-get install -y ufw
  ufw --force reset
  ufw default deny incoming
  ufw default allow outgoing

  IFS=',' read -ra PORTS <<< "$UFW_ALLOW_PORTS"
  for p in "${PORTS[@]}"; do
    p_trim="$(echo "$p" | xargs)"
    [[ -n "$p_trim" ]] && ufw allow "$p_trim"/tcp || true
  done

  if [[ "$SSH_PORT" != "22" ]]; then
    ufw delete allow 22/tcp || true
    ufw allow ${SSH_PORT}/tcp
  fi

  ufw --force enable
  ufw status verbose
}

post_notes(){
cat <<EOF

-------------------------------------------------
✅ Secure stack complete

SSH:
- Port: ${SSH_PORT}, root login disabled
- PasswordAuthentication: $( [[ "$DISABLE_SSH_PASSWORD" == "yes" ]] && echo "no" || echo "yes" )
- AllowUsers: ${ALLOW_SSH_USERS:-<none>}

Webmin:
- https://<server-ip>:10000 (system users)

Fail2ban:
- Check: fail2ban-client status sshd

UFW:
- Default deny incoming / allow outgoing
- Allowed TCP: ${UFW_ALLOW_PORTS}
-------------------------------------------------
EOF
}

main(){
  need_root
  detect_debian
  install_openssh
  install_webmin
  install_fail2ban
  setup_ufw
  post_notes
  green "All done (secure-stack)."
}

main "$@"
