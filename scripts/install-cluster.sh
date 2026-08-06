#!/usr/bin/env bash
#
# install-cluster.sh
#
# Wrapper to run Ansible playbook(s) to provision and initialize the Kubernetes cluster.
# Performs pre-checks, optionally installs Ansible (if missing), and runs ansible-playbook with sensible defaults.
#
# Usage:
#   ./install-cluster.sh [--inventory ansible/inventory.yml] [--playbook ansible/site.yml] [--ansible-venv .venv]
#
# Environment variables:
#   ANSIBLE_PLAYBOOK   - path to ansible-playbook binary (default: ansible-playbook from PATH)
#   INVENTORY          - path to inventory file (default: ansible/inventory.yml)
#   PLAYBOOK           - path to playbook (default: ansible/site.yml)
#   ANSIBLE_VENV       - virtualenv path to create/use for Ansible (default: .venv)
#
set -euo pipefail

# Defaults
ANSIBLE_PLAYBOOK_BIN="${ANSIBLE_PLAYBOOK:-ansible-playbook}"
INVENTORY="${1:-ansible/inventory.yml}"
PLAYBOOK="${2:-ansible/site.yml}"
ANSIBLE_VENV="${ANSIBLE_VENV:-.venv}"

usage() {
  cat <<EOF
Usage: $0 [inventory] [playbook]

Defaults:
  inventory: ${INVENTORY}
  playbook:  ${PLAYBOOK}

Options:
  --inventory PATH    Specify inventory file
  --playbook PATH     Specify playbook file
  --venv PATH         Create/use Python virtualenv for Ansible (default: ${ANSIBLE_VENV})
  -h, --help          Show this help
EOF
}

# Parse flags (simple)
while [[ $# -gt 0 ]]; do
  case "$1" in
    --inventory) INVENTORY="$2"; shift 2;;
    --playbook) PLAYBOOK="$2"; shift 2;;
    --venv) ANSIBLE_VENV="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) break;;
  esac
done

# Basic checks
if [[ ! -f "${INVENTORY}" ]]; then
  echo "Inventory file not found: ${INVENTORY}"
  exit 1
fi

if [[ ! -f "${PLAYBOOK}" ]]; then
  echo "Playbook file not found: ${PLAYBOOK}"
  exit 1
fi

# Ensure Python3 available
if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required. Please install python3 and re-run."
  exit 1
fi

# Create virtualenv and install requirements if ansible not present
if ! command -v ansible-playbook >/dev/null 2>&1; then
  echo "ansible-playbook not found in PATH. Creating virtualenv at ${ANSIBLE_VENV} and installing dependencies."
  python3 -m venv "${ANSIBLE_VENV}"
  # shellcheck disable=SC1090
  source "${ANSIBLE_VENV}/bin/activate"
  pip install --upgrade pip
  if [[ -f requirements.txt ]]; then
    pip install -r requirements.txt
  else
    pip install ansible==7.5.0
  fi
  ANSIBLE_PLAYBOOK_BIN="${ANSIBLE_VENV}/bin/ansible-playbook"
else
  ANSIBLE_PLAYBOOK_BIN="$(command -v ansible-playbook)"
fi

echo "Using ansible-playbook: ${ANSIBLE_PLAYBOOK_BIN}"
echo "Inventory: ${INVENTORY}"
echo "Playbook: ${PLAYBOOK}"

# Run ansible-playbook with forks and become
# We pass --ssh-extra-args to avoid host key checking prompts in CI; in production consider managing known_hosts.
ANSIBLE_EXTRA_ARGS=(
  "--inventory" "${INVENTORY}"
  "${PLAYBOOK}"
  "--forks" "10"
  "--become"
  "--ssh-extra-args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'"
)

# Print command for transparency
echo "Running: ${ANSIBLE_PLAYBOOK_BIN} ${ANSIBLE_EXTRA_ARGS[*]}"
# Use eval to allow ssh-extra-args quoting to be passed through
eval "${ANSIBLE_PLAYBOOK_BIN} ${ANSIBLE_EXTRA_ARGS[*]}"

RC=$?
if [[ ${RC} -ne 0 ]]; then
  echo "Ansible playbook failed with exit code ${RC}"
  exit ${RC}
fi

echo "Ansible playbook completed successfully."

# Post-install hints
cat <<EOF

Next steps:
  - Copy kubeconfig from master to your workstation:
      scp -i <key> ${ANSIBLE_VENV:+}ubuntu@<master-ip>:/home/ubuntu/.kube/config ~/.kube/config
    or use the generated inventory to find master IP.

  - Install Helm on your workstation:
      curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

  - Add required Helm repos and install infrastructure charts:
      helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
      helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
      helm repo add grafana https://grafana.github.io/helm-charts
      helm repo update

  - Apply network policies and RBAC manifests:
      kubectl apply -f infrastructure/rbac/ci-user.yaml
      kubectl apply -f infrastructure/network-policies/default-deny.yaml

EOF

exit 0
