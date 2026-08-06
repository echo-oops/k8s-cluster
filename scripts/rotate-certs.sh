#!/usr/bin/env bash
#
# rotate-certs.sh
#
# Rotate Kubernetes control-plane certificates using kubeadm and restart kubelet.
# This script performs safe checks, backs up existing certs, renews via kubeadm, and restarts kubelet.
#
# Usage:
#   sudo ./rotate-certs.sh [--kubeconfig /etc/kubernetes/admin.conf] [--backup-dir /var/backups/k8s-certs]
#
# Environment variables:
#   KUBECONFIG      - path to kubeconfig (default: /etc/kubernetes/admin.conf)
#   BACKUP_DIR      - directory to store certificate backups (default: /var/backups/k8s-certs)
#
set -euo pipefail

KUBECONFIG="${KUBECONFIG:-/etc/kubernetes/admin.conf}"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/k8s-certs}"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"

usage() {
  cat <<EOF
Usage: sudo $0 [options]

Options:
  --kubeconfig PATH   Path to kubeconfig (default: ${KUBECONFIG})
  --backup-dir PATH   Directory to store certificate backups (default: ${BACKUP_DIR})
  -h, --help          Show this help and exit
EOF
}

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --kubeconfig) KUBECONFIG="$2"; shift 2;;
    --backup-dir) BACKUP_DIR="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1"; usage; exit 2;;
  esac
done

if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root or with sudo."
  exit 1
fi

# Ensure kubeadm exists
if ! command -v kubeadm >/dev/null 2>&1; then
  echo "kubeadm not found. Install kubeadm on the control-plane node and re-run."
  exit 1
fi

# Ensure kubectl exists
if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl not found. Install kubectl on the control-plane node and re-run."
  exit 1
fi

# Ensure kubeconfig exists
if [[ ! -f "${KUBECONFIG}" ]]; then
  echo "Kubeconfig not found at ${KUBECONFIG}. Are you on a control-plane node?"
  exit 1
fi

# Backup existing certs
mkdir -p "${BACKUP_DIR}"
chmod 700 "${BACKUP_DIR}"
BACKUP_ARCHIVE="${BACKUP_DIR}/k8s-certs-backup-${TIMESTAMP}.tar.gz"

echo "Backing up /etc/kubernetes/pki to ${BACKUP_ARCHIVE}"
tar -czf "${BACKUP_ARCHIVE}" -C /etc/kubernetes pki || { echo "Backup failed"; exit 1; }
echo "Backup complete"

# Check certificate expiry summary
echo "Current certificate expiry (kubectl):"
kubectl --kubeconfig="${KUBECONFIG}" get csr --no-headers || true
echo "kubeadm certs check-expiration:"
kubeadm certs check-expiration || true

# Renew all certificates
echo "Renewing all certificates via kubeadm"
kubeadm certs renew all

# kubeadm may output renewed certs; verify
echo "Post-renewal certificate expiry:"
kubeadm certs check-expiration || true

# Restart kubelet to pick up new certs
echo "Restarting kubelet service"
if command -v systemctl >/dev/null 2>&1; then
  systemctl daemon-reload || true
  systemctl restart kubelet
  systemctl status kubelet --no-pager || true
else
  echo "systemctl not available; please restart kubelet manually"
fi

# Optional: rotate kubeadm certificates for kube-proxy or other components if needed
echo "If you use external components that rely on old certs, rotate them accordingly."

echo "Certificate rotation completed. Backup stored at: ${BACKUP_ARCHIVE}"
exit 0
