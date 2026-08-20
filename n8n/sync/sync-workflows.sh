#!/usr/bin/env bash
set -euo pipefail

project_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$project_directory"

docker compose up -d n8n
docker compose exec -T n8n n8n export:workflow --all --output=/home/node/.n8n/talentflow-current-workflows.json
docker compose exec -T n8n node /workspace/sync/merge-workflows.mjs \
  /workspace/workflows \
  /home/node/.n8n/talentflow-current-workflows.json \
  /home/node/.n8n/talentflow-workflows-to-import.json

docker compose stop n8n
docker compose run --rm --no-deps n8n import:workflow \
  --input=/home/node/.n8n/talentflow-workflows-to-import.json

mapfile -t active_workflow_ids < <(
  docker compose run --rm --no-deps --entrypoint node n8n -e \
    "const fs=require('fs'); for(const w of JSON.parse(fs.readFileSync('/home/node/.n8n/talentflow-workflows-to-import.json','utf8'))) if(w.active) console.log(w.id)"
)
for workflow_id in "${active_workflow_ids[@]}"; do
  docker compose run --rm --no-deps n8n publish:workflow --id="$workflow_id"
done
docker compose up -d n8n frontend

echo "TalentFlow workflows synchronized with n8n."
