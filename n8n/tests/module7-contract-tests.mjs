import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const summarySchema = JSON.parse(readFileSync("n8n/schemas/IA02-summary.schema.json", "utf8"));
const questionsSchema = JSON.parse(readFileSync("n8n/schemas/IA03-questions.schema.json", "utf8"));
const summaryPrompt = readFileSync("n8n/prompts/PROMPT-IA-02-resumen.md", "utf8");
const questionsPrompt = readFileSync("n8n/prompts/PROMPT-IA-03-preguntas.md", "utf8");

assert.deepEqual(summarySchema.required, ["summary", "key_points"]);
assert.equal(questionsSchema.properties.questions.maxItems, 5);
assert.match(summaryPrompt, /No recomiendes contratación o\s+descarte/i);
assert.match(questionsPrompt, /No afirmes que una tecnología\s+fue usada profesionalmente sin evidencia laboral/i);

const context = {
  experienceIds: new Set(["EXP-2"]),
  topics: new Set(["docker", "aws", "sql"]),
};

function validateQuestion(question) {
  const normalized = question.topic.toLowerCase();
  assert([...context.topics].some((topic) => normalized.includes(topic) || topic.includes(normalized)), "skill inexistente");
  if (question.source_type === "WORK_EXPERIENCE") {
    assert(context.experienceIds.has(question.experience_id), "experiencia inexistente");
  }
}

validateQuestion({
  topic: "Uso profesional de Docker", source_type: "WORK_EXPERIENCE", experience_id: "EXP-2",
  question: "¿Cómo utilizaste Docker durante tu trabajo en Empresa X?",
});
validateQuestion({
  topic: "AWS", source_type: "DECLARED_SKILL", experience_id: null,
  question: "Indicas conocimiento de AWS. ¿En qué contextos lo has utilizado?",
});
context.topics.add("c#");
validateQuestion({
  topic: "Requisito obligatorio faltante C#", source_type: "REQUIREMENT_VALIDATION", experience_id: null,
  question: "¿Cuentas con proyectos donde hayas utilizado C#?",
});
assert.throws(() => validateQuestion({
  topic: "Kubernetes", source_type: "DECLARED_SKILL", experience_id: null,
  question: "¿Cómo utilizaste Kubernetes?",
}), /skill inexistente/);

console.log("OK: contratos IA-02/IA-03, evidencia Docker, AWS declarada y skill inexistente");
