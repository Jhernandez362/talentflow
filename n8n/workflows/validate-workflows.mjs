import { readFileSync, readdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const workflowDirectory = dirname(fileURLToPath(import.meta.url));
const workflowFiles = readdirSync(workflowDirectory)
  .filter((file) => /^(TF-ADMIN|TF-PUBLIC|TF-M4|TF-M5|TF-M6|TF-M7)-.*\.json$/.test(file))
  .sort();

const errors = [];

for (const file of workflowFiles) {
  let workflow;

  try {
    workflow = JSON.parse(readFileSync(join(workflowDirectory, file), "utf8"));
  } catch (error) {
    errors.push(`${file}: JSON invalido (${error.message})`);
    continue;
  }

  for (const node of workflow.nodes ?? []) {
    if (
      node.type !== "n8n-nodes-base.postgres" ||
      node.parameters?.operation !== "executeQuery"
    ) {
      continue;
    }

    const query = node.parameters.query ?? "";
    const options = node.parameters.options ?? {};

    if ("queryParams" in options) {
      errors.push(
        `${file} / ${node.name}: usa queryParams, una opcion que n8n 2.31 no reconoce`,
      );
    }

    if (/\$\d+/.test(query) && !options.queryReplacement) {
      errors.push(
        `${file} / ${node.name}: la consulta usa parametros posicionales pero no define queryReplacement`,
      );
    }
  }
}

if (errors.length > 0) {
  console.error(errors.join("\n"));
  process.exitCode = 1;
} else {
  console.log(`OK: ${workflowFiles.length} workflows ADMIN/PUBLIC/M4/M5/M6/M7 son importables y sus consultas estan parametrizadas.`);
}
