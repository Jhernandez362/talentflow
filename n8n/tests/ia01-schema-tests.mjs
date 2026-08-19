import assert from "node:assert/strict";

const base = {
  experiencia_total_anios: null,
  experiencias: [], educacion: [], cursos: [], certificaciones: [], idiomas: [],
  habilidades: [], habilidades_declaradas_no_verificadas: [], advertencias: [],
};

const cases = [
  {
    name: "varias experiencias sin doble conteo",
    output: { ...base, experiencia_total_anios: 4, experiencias: [
      { id: "EXP-1", empresa: "A", cargo: "Dev", fecha_inicio: "2020-01", fecha_fin: "2022-01", duracion_meses: 24, funciones: [], tecnologias: ["Java"] },
      { id: "EXP-2", empresa: "B", cargo: "Dev", fecha_inicio: "2022-01", fecha_fin: "2024-01", duracion_meses: 24, funciones: [], tecnologias: ["PostgreSQL"] },
    ] },
  },
  {
    name: "habilidades solamente listadas",
    output: { ...base, habilidades: [{ nombre: "Docker", evidencia_laboral: false, experiencia_ids: [] }] },
  },
  {
    name: "curso y certificacion",
    output: { ...base, cursos: [{ nombre: "SQL", institucion: "Instituto", fecha: null }], certificaciones: ["AWS Practitioner"] },
  },
  {
    name: "campos faltantes representados sin invencion",
    output: { ...base, advertencias: ["No hay fechas suficientes para calcular experiencia total"] },
  },
];

const prohibited = new Set(["score", "compatibilidad", "recomendacion", "edad", "genero", "género", "nacionalidad", "religion", "religión", "discapacidad"]);
const requiredArrays = ["experiencias", "educacion", "cursos", "certificaciones", "idiomas", "habilidades", "habilidades_declaradas_no_verificadas", "advertencias"];

function validate(value) {
  assert(value && typeof value === "object" && !Array.isArray(value));
  requiredArrays.forEach((key) => assert(Array.isArray(value[key]), `${key} debe ser array`));
  const walk = (current) => {
    if (!current || typeof current !== "object") return;
    for (const [key, child] of Object.entries(current)) {
      assert(!prohibited.has(key.toLowerCase()), `campo prohibido: ${key}`);
      walk(child);
    }
  };
  walk(value);
  const ids = new Set(value.experiencias.map(({ id }) => id));
  value.habilidades.forEach(({ experiencia_ids = [] }) => experiencia_ids.forEach((id) => assert(ids.has(id), `evidencia inexistente: ${id}`)));
}

cases.forEach(({ output }) => validate(output));
assert.throws(() => validate({ ...base, score: 90 }), /campo prohibido/);
assert.throws(() => validate({ ...base, edad: 30 }), /campo prohibido/);
console.log(`OK: ${cases.length} casos IA-01 y 2 controles negativos`);
