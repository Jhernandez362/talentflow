import fs from 'node:fs';
import path from 'node:path';

const [sourceDirectory, currentExport, outputFile] = process.argv.slice(2);

if (!sourceDirectory || !currentExport || !outputFile) {
  throw new Error('Usage: node merge-workflows.mjs <source-dir> <current-export> <output-file>');
}

const exported = JSON.parse(fs.readFileSync(currentExport, 'utf8'));
const currentWorkflows = Array.isArray(exported) ? exported : [exported];
const currentById = new Map(currentWorkflows.filter(({ id }) => id).map((workflow) => [workflow.id, workflow]));
const currentByName = new Map(currentWorkflows.map((workflow) => [workflow.name, workflow]));
const credentialsByNodeType = new Map();

for (const workflow of currentWorkflows) {
  for (const node of workflow.nodes ?? []) {
    if (node.credentials && !credentialsByNodeType.has(node.type)) {
      credentialsByNodeType.set(node.type, node.credentials);
    }
  }
}

function preserveLocalValues(source, current) {
  if (typeof source === 'string' && source.startsWith('REPLACE_WITH_')) {
    return typeof current === 'string' && !current.startsWith('REPLACE_WITH_') ? current : source;
  }
  if (Array.isArray(source)) {
    return source.map((value, index) => preserveLocalValues(value, current?.[index]));
  }
  if (source && typeof source === 'object') {
    return Object.fromEntries(
      Object.entries(source).map(([key, value]) => [key, preserveLocalValues(value, current?.[key])]),
    );
  }
  return source;
}

const sourceFiles = fs.readdirSync(sourceDirectory).filter((file) => file.endsWith('.json')).sort();
const merged = sourceFiles.map((file) => {
  const source = JSON.parse(fs.readFileSync(path.join(sourceDirectory, file), 'utf8'));
  const current = currentById.get(source.id) ?? currentByName.get(source.name);
  if (!current) return source;

  const currentNodes = new Map(current.nodes.map((node) => [node.id ?? node.name, node]));
  source.id = current.id;
  source.active = current.active;
  source.nodes = source.nodes.map((node) => {
    const localNode = currentNodes.get(node.id ?? node.name);
    const mergedNode = preserveLocalValues(node, localNode);
    const credentials = localNode?.credentials ?? credentialsByNodeType.get(node.type);
    if (credentials) mergedNode.credentials = credentials;
    return mergedNode;
  });
  return source;
});

fs.writeFileSync(outputFile, JSON.stringify(merged));
console.log(`Prepared ${merged.length} workflows for synchronization.`);
