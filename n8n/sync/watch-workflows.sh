#!/usr/bin/env bash
set -euo pipefail

project_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
workflow_directory="$project_directory/n8n/workflows"
sync_script="$project_directory/n8n/sync/sync-workflows.sh"

checksum() {
  find "$workflow_directory" -maxdepth 1 -type f -name '*.json' -print0 \
    | sort -z \
    | xargs -0 sha256sum \
    | sha256sum \
    | cut -d' ' -f1
}

previous_checksum="$(checksum)"
echo "Watching $workflow_directory (Ctrl+C to stop)."

while sleep 2; do
  current_checksum="$(checksum)"
  if [[ "$current_checksum" != "$previous_checksum" ]]; then
    echo "Workflow change detected; synchronizing..."
    "$sync_script"
    previous_checksum="$current_checksum"
  fi
done
