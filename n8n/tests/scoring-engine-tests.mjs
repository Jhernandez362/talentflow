import assert from "node:assert/strict";
import { calculateCompatibility } from "../scoring/deterministic-compatibility.mjs";

const criteria = [
  { id: "react", name: "React", aliases: ["React.js", "ReactJS"], criterion_type: "TECNOLOGIA", weight: 40, is_required: true, evaluation_order: 1 },
  { id: "experience", name: "Experiencia", criterion_type: "EXPERIENCIA", weight: 20, evaluation_rule: { required_years: 2 }, evaluation_order: 2 },
  { id: "education", name: "Educacion", criterion_type: "EDUCACION", weight: 40, evaluation_rule: { minimum_level: "TECNICO" }, evaluation_order: 3 },
];
const vacancy = { minimum_experience_months: 24, expected_experience_min_months: 24, expected_experience_max_months: 48, minimum_education: "TECNICO" };
const candidate = (overrides = {}) => ({ experiencia_total_anios: 2, habilidades: [{ nombre: "ReactJS", evidencia_laboral: true }], educacion: [{ nivel: "TECNICO" }], experiencias: [], ...overrides });
const score = (data) => calculateCompatibility({ candidate: data, vacancy, criteria, desirables: [{ name: "Docker" }], addedValues: [{ name: "AWS" }], scoringVersion: 1 });

assert.equal(score(candidate()).score, 100); // A
assert.equal(score(candidate({ habilidades: [], educacion: [], experiencia_total_anios: 0 })).score, 0); // B
assert.equal(score(candidate({ experiencia_total_anios: 1 })).score, 90); // C
assert.equal(score(candidate({ experiencia_total_anios: 5 })).score, 100); // D
assert.deepEqual(score(candidate({ habilidades: [] })).mandatory_missing, ["React"]); // E
const desirableResult = score(candidate({ habilidades: [{ nombre: "ReactJS", evidencia_laboral: true }, { nombre: "Docker", evidencia_laboral: false }] }));
assert.equal(desirableResult.score, 100); // F
assert.deepEqual(desirableResult.desired_found, ["Docker"]);
const addedValueResult = score(candidate({ cursos: [{ nombre: "AWS" }] }));
assert.equal(addedValueResult.score, 100); // G
assert.deepEqual(addedValueResult.added_value, ["AWS"]);
assert.equal(score(candidate()).criteria[0].matched, true); // H
assert.equal(score(candidate({ habilidades: [{ nombre: "Preact", evidencia_laboral: true }] })).criteria[0].matched, false); // I
assert.deepEqual(score(candidate()), score(candidate()));
assert.ok(score(candidate({ experiencia_total_anios: 10 })).score <= 100);
assert.equal(score(candidate({ habilidades: [], habilidades_declaradas_no_verificadas: ["ReactJS"] })).criteria[0].matched, false);
assert.equal(score(candidate({ experiencia_total_anios: 1 })).seniority_fit, "POR_DEBAJO");
assert.equal(score(candidate({ experiencia_total_anios: 5 })).seniority_fit, "POR_ENCIMA");
assert.equal(score(candidate({ experiencia_total_anios: 2 })).priority, "ALTA");
console.log("OK: pruebas A-I del motor deterministico pasaron");
