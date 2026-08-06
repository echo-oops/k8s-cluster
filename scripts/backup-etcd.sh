#!/usr/bin/env bash
#
# backup-etcd.sh
#
# Creates an etcd snapshot from a control-plane node and optionally uploads it to S3.
# Designed to be idempotent and safe for repeated runs.
#
# Usage:
#   sudo ./backup-etcd.sh [--kubeconfig /etc/kubernetes/admin.conf] [--out-dir /var/backups/etcd] [--s3-bucket my-bucket] [--retention 30]
#
# Environment variables (alternatively pass via flags):
#   KUBECONFIG         - path to kubeconfig (default: /etc/kubernetes/admin.conf)
#   SNAPSHOT_DIR       - local directory to store snapshots (default: /var/backups/etcd)
#   ETCDCTL_BIN        - path to etcdctl (default: /usr/bin/etcdctl)
#   ETCD_ENDPOINT      - etcd endpoint (default: https://127.0.0.1:2379)
#   ETCD_CERT          - client cert for etcd
#   ETCD_KEY           - client key for etcd
#   ETCD_CA            - CA cert for etcd
#   S3_BUCKET          - optional S3 bucket to upload snapshot
#   S3_PREFIX          - optional S3 prefix (default: etcd)
#   RETENTION_DAYS     - optional retention in days for local cleanup (default: 30)
#
set -euo pipefail

# Defaults
ETCDCTL_BIN="${ETCDCTL_BIN:-/usr/bin/etcdctl}"
KUBECONFIG="${KUBECONFIG:-/etc/kubernetes/admin.conf}"
SNAPSHOT_DIR="${SNAPSHOT_DIR:-/var/backups/etcd}"
ETCD_ENDPOINT="${ETCD_ENDPOINT:-https://127.0.0.1:2379}"
ETCD_CERT="${ETCD_CERT:-/etc/kubernetes/pki/etcd/peer.crt}"
ETCD_KEY="${ETCD_KEY:-/etc/kubernetes/pki/etcd/peer.key}"
ETCD_CA="${ETCD_CA:-/etc/kubernetes/pki/etcd/ca.crt}"
S3_BUCKET="${S3_BUCKET:-}"
S3_PREFIX="${S3_PREFIX:-etcd}"
RETENTION_DAYS="${RETENTION_DAYS:-30}"

# Helper: print usage
usage() {
  cat <<EOF
Usage: sudo $0 [options]

Options:
  --kubeconfig PATH     Path to kubeconfig (default: ${KUBECONFIG})
  --out-dir PATH        Directory to store snapshots (default: ${SNAPSHOT_DIR})
  --s3-bucket NAME      Upload snapshot to S3 bucket (optional)
  --s3-prefix PREFIX    S3 prefix/folder (default: ${S3_PREFIX})
  --retention DAYS      Remove local snapshots older than DAYS (default: ${RETENTION_DAYS})
  -h, --help            Show this help and exit

Environment variables can be used instead of flags.
EOF
}

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --kubeconfig) KUBECONFIG="$2"; shift 2;;
    --out-dir) SNAPSHOT_DIR="$2"; shift 2;;
    --s3-bucket) S3_BUCKET="$2"; shift 2;;
    --s3-prefix) S3_PREFIX="$2"; shift 2;;
    --retention) RETENTION_DAYS="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1"; usage; exit 2;;
  esac
done

# Ensure running as root (etcdctl may need access to certs)
if [[ $EUID -ne 0 ]]; then
  echo "This script should be run as root or with sudo. Re-run with sudo."
  exit 1
fi

# Ensure etcdctl exists
if ! command -v "${ETCDCTL_BIN}" >/dev/null 2>&1; then
  echo "etcdctl not found at ${ETCDCTL_BIN}. Attempting to locate etcdctl in PATH..."
  if command -v etcdctl >/dev/null 2>&1; then
    ETCDCTL_BIN="$(command -v etcdctl)"
    echo "Found etcdctl at ${ETCDCTL_BIN}"
  else
    echo "etcdctl is required. Install etcdctl (etcd v3) and re-run."
    exit 1
  fi
fi

# Ensure aws cli if S3 upload requested
if [[ -n "${S3_BUCKET}" ]]; then
  if ! command -v aws >/dev/null 2>&1; then
    echo "AWS CLI not found but S3 upload requested. Install awscli or unset S3_BUCKET."
    exit 1
  fi
fi

# Create snapshot directory
mkdir -p "${SNAPSHOT_DIR}"
chmod 700 "${SNAPSHOT_DIR}"

TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
SNAPSHOT_FILE="${SNAPSHOT_DIR}/etcd-snapshot-${TIMESTAMP}.db"

echo "Starting etcd snapshot at ${TIMESTAMP}"
echo "Snapshot file: ${SNAPSHOT_FILE}"

# Export env for etcdctl v3
export ETCDCTL_API=3
export ETCDCTL_ENDPOINTS="${ETCD_ENDPOINT}"

# If certs exist, pass them
ETCDCTL_ARGS=()
if [[ -f "${ETCD_CA}" ]]; then
  ETCDCTL_ARGS+=(--cacert "${ETCD_CA}")
fi
if [[ -f "${ETCD_CERT}" ]]; then
  ETCDCTL_ARGS+=(--cert "${ETCD_CERT}")
fi
if [[ -f "${ETCD_KEY}" ]]; then
  ETCDCTL_ARGS+=(--key "${ETCD_KEY}")
fi

# Run snapshot save
echo "Running: ${ETCDCTL_BIN} snapshot save ${SNAPSHOT_FILE} ${ETCDCTL_ARGS[*]}"
"${ETCDCTL_BIN}" snapshot save "${SNAPSHOT_FILE}" "${ETCDCTL_ARGS[@]}"

if [[ $? -ne 0 ]]; then
  echo "etcd snapshot failed"
  exit 1
fi

echo "Snapshot saved locally: ${SNAPSHOT_FILE}"

# Optional: upload to S3
if [[ -n "${S3_BUCKET}" ]]; then
  S3_KEY="${S3_PREFIX}/$(basename "${SNAPSHOT_FILE}")"
  echo "Uploading snapshot to s3://${S3_BUCKET}/${S3_KEY}"
  aws s3 cp "${SNAPSHOT_FILE}" "s3://${S3_BUCKET}/${S3_KEY}" --only-show-errors
  if [[ $? -ne 0 ]]; then
    echo "Warning: upload to S3 failed"
  else
    echo "Upload complete"
  fi
fi

# Cleanup old snapshots
if [[ -n "${RETENTION_DAYS}" && "${RETENTION_DAYS}" -gt 0 ]]; then
  echo "Removing local snapshots older than ${RETENTION_DAYS} days in ${SNAPSHOT_DIR}"
  find "${SNAPSHOT_DIR}" -type f -name "etcd-snapshot-*.db" -mtime +"${RETENTION_DAYS}" -print -exec rm -f {} \; || true
fi

echo "etcd snapshot process completed successfully."
exit 0
