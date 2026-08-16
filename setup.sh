#!/usr/bin/env bash
#
# setup.sh — automates the server-side setup of a WireGuard VPN on
# Oracle Linux 9 (tested on an Oracle Cloud Always Free VM.Standard.E2.1.Micro).
#
# This script handles what CAN be automated. It prints instructions for the
# steps that must be done manually (Oracle Cloud console networking, and
# writing wg0.conf with your actual keys/peers).
#
# Usage: sudo ./setup.sh

set -euo pipefail

WG_DIR="/etc/wireguard"
SERVER_PRIVATE_KEY="${WG_DIR}/server_private.key"
SERVER_PUBLIC_KEY="${WG_DIR}/server_public.key"
WG_PORT="51820"
WG_INTERFACE="wg0"

if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root (try: sudo ./setup.sh)" >&2
  exit 1
fi

echo "==> Installing wireguard-tools (using fast repo flags to skip Ksplice metadata)..."
dnf install -y --disablerepo="*" --enablerepo="ol9_baseos_latest,ol9_appstream" wireguard-tools

echo "==> Enabling IP forwarding..."
if ! grep -q '^net.ipv4.ip_forward *= *1' /etc/sysctl.d/99-wireguard.conf 2>/dev/null; then
  echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/99-wireguard.conf
fi
sysctl -p /etc/sysctl.d/99-wireguard.conf

echo "==> Generating server keypair (if not already present)..."
mkdir -p "${WG_DIR}"
chmod 700 "${WG_DIR}"
if [[ -f "${SERVER_PRIVATE_KEY}" && -f "${SERVER_PUBLIC_KEY}" ]]; then
  echo "    Server keypair already exists at ${WG_DIR}, skipping generation."
else
  umask 077
  wg genkey | tee "${SERVER_PRIVATE_KEY}" | wg pubkey > "${SERVER_PUBLIC_KEY}"
  echo "    Generated ${SERVER_PRIVATE_KEY} and ${SERVER_PUBLIC_KEY}"
fi

echo "==> Opening UDP/${WG_PORT} in firewalld and enabling masquerade..."
firewall-cmd --permanent --add-port="${WG_PORT}/udp"
firewall-cmd --permanent --add-masquerade
firewall-cmd --reload

echo ""
echo "================================================================"
echo " Automated steps complete. Manual steps still required:"
echo "================================================================"
echo ""
echo "1. ORACLE CLOUD CONSOLE — NETWORKING"
echo "   a. Ensure your VCN has an internet gateway. If your instance"
echo "      has no outbound internet access, use the VCN's"
echo "      'Connect public subnet to internet' quick action."
echo "   b. Assign a public IP (not automatic on Always Free VMs):"
echo "      Instance -> Networking -> Attached VNICs -> [VNIC] ->"
echo "      IP Management -> Edit (on the primary private IP) ->"
echo "      assign an ephemeral public IP."
echo "   c. Add an ingress rule to your VCN's Security List (or NSG):"
echo "      Protocol UDP, Source 0.0.0.0/0, Destination Port ${WG_PORT}."
echo ""
echo "2. WRITE ${WG_DIR}/${WG_INTERFACE}.conf"
echo "   Your generated server private key is in:"
echo "     ${SERVER_PRIVATE_KEY}"
echo "   Your generated server public key (share this with clients) is in:"
echo "     ${SERVER_PUBLIC_KEY}"
echo ""
echo "   Create ${WG_DIR}/${WG_INTERFACE}.conf with contents like:"
echo ""
echo "     [Interface]"
echo "     Address = 10.8.0.1/24"
echo "     ListenPort = ${WG_PORT}"
echo "     PrivateKey = <contents of ${SERVER_PRIVATE_KEY}>"
echo ""
echo "     [Peer]"
echo "     # replace with your client's public key"
echo "     PublicKey = CLIENT_PUBLIC_KEY_HERE"
echo "     AllowedIPs = 10.8.0.2/32"
echo ""
echo "   NOTE: wg0.conf and *.key are gitignored by this repo — never"
echo "   commit real key values."
echo ""
echo "3. ENABLE AND START THE SERVICE"
echo "     sudo systemctl enable --now wg-quick@${WG_INTERFACE}"
echo ""
echo "4. VERIFY FROM A CONNECTED CLIENT"
echo "     curl https://ifconfig.me"
echo "   should return YOUR_SERVER_IP, not the client's home IP."
echo "================================================================"
