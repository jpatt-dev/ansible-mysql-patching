#!/usr/bin/env bash
set -euo pipefail
export PATH="$HOME/.local/share/pipx/venvs/ansible/bin:$HOME/.local/bin:$PATH"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export ANSIBLE_ROLES_PATH="$ROOT/roles"
cd "$(dirname "$0")"

echo "===== Phase 0 ansible regressions"
ansible-playbook -i inventory.ini test_phase0.yml
echo "PHASE0_ANSIBLE_OK"
