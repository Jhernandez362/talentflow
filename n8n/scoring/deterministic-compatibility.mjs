const EDUCATION_LEVELS = Object.freeze([
  "NINGUNA",
  "BACHILLER",
  "TECNICO",
  "TECNOLOGO",
  "PROFESIONAL",
  "ESPECIALIZACION",
  "MAESTRIA",
  "DOCTORADO",
]);

const EDUCATION_ALIASES = new Map([
  ["NONE", "NINGUNA"],
  ["HIGH_SCHOOL", "BACHILLER"],
  ["BACHILLERATO", "BACHILLER"],
  ["TECHNICAL", "TECNICO"],
  ["TECNICO", "TECNICO"],
  ["TECHNOLOGIST", "TECNOLOGO"],
  ["TECHNOLOGO", "TECNOLOGO"],
  ["PROFESSIONAL", "PROFESIONAL"],
  ["SPECIALIZATION", "ESPECIALIZACION"],
  ["MASTER", "MAESTRIA"],
  ["DOCTORATE", "DOCTORADO"],
]);

export function normalize(value) {
  return String(value ?? "")
    .trim()
    .toLocaleLowerCase("es")
    .replace(/\s+/g, " ");
}

function textValues(candidate) {
  const values = [];
  for (const skill of candidate.habilidades ?? []) {
    values.push(typeof skill === "string" ? skill : skill.nombre);
  }
  // Las habilidades declaradas que IA-01 no verifico se conservan como
  // contexto, pero nunca participan en el score.
  for (const experience of candidate.experiencias ?? []) {
    values.push(...(experience.tecnologias ?? []), ...(experience.funciones ?? []));
  }
  values.push(...(candidate.certificaciones ?? []), ...(candidate.idiomas ?? []));
  for (const course of candidate.cursos ?? []) values.push(course.nombre);
  for (const education of candidate.educacion ?? []) {
    values.push(education.nivel, education.titulo, education.campo);
  }
  return new Set(values.filter(Boolean).map(normalize));
}

function criterionAliases(criterion) {
  return [criterion.name, ...(criterion.aliases ?? []), ...(criterion.evaluation_rule?.aliases ?? [])]
    .filter(Boolean)
    .map(normalize);
}

function hasExactMatch(values, criterion) {
  return criterionAliases(criterion).some((alias) => values.has(alias));
}

function hasWorkEvidence(candidate, criterion) {
  const aliases = new Set(criterionAliases(criterion));
  return (candidate.habilidades ?? []).some((skill) => {
    const name = typeof skill === "string" ? skill : skill.nombre;
    return aliases.has(normalize(name)) && typeof skill === "object" && skill.evidencia_laboral === true;
  }) || (candidate.experiencias ?? []).some((experience) =>
    (experience.tecnologias ?? []).some((technology) => aliases.has(normalize(technology))),
  );
}

function candidateExperienceYears(candidate) {
  const value = candidate.experiencia_total_anios ?? candidate.experiencia_anios ?? candidate.experience_years;
  const number = Number(value);
  return Number.isFinite(number) && number >= 0 ? number : 0;
}

function requiredExperienceYears(criterion, vacancy) {
  const configured = Number(criterion.evaluation_rule?.required_years);
  if (Number.isFinite(configured) && configured >= 0) return configured;
  const months = Number(vacancy.minimum_experience_months);
  return Number.isFinite(months) && months >= 0 ? months / 12 : 0;
}

function normalizeEducation(value) {
  const normalized = normalize(value).toUpperCase().replace(/\s+/g, "_");
  return EDUCATION_ALIASES.get(normalized) ?? (EDUCATION_LEVELS.includes(normalized) ? normalized : null);
}

function candidateEducationLevel(candidate) {
  return Math.max(0, ...(candidate.educacion ?? []).map((item) => EDUCATION_LEVELS.indexOf(normalizeEducation(item.nivel ?? item.level))).filter((level) => level >= 0));
}

function requiredEducationLevel(criterion, vacancy) {
  return normalizeEducation(criterion.evaluation_rule?.minimum_level ?? vacancy.minimum_education) ?? "NINGUNA";
}

function calculateSeniorityFit(candidateYears, vacancy, fallbackYears) {
  const minimum = Number(vacancy.expected_experience_min_months ?? vacancy.minimum_experience_months);
  const maximum = Number(vacancy.expected_experience_max_months);
  const minYears = Number.isFinite(minimum) && minimum >= 0 ? minimum / 12 : fallbackYears;
  const maxYears = Number.isFinite(maximum) && maximum >= 0 ? maximum / 12 : null;
  if (candidateYears < minYears) return "POR_DEBAJO";
  if (maxYears !== null && candidateYears > maxYears) return "POR_ENCIMA";
  return "ALINEADO";
}

function collectConfiguredMatches(candidate, requirements) {
  const values = textValues(candidate);
  return requirements.map((requirement) => ({
    name: requirement.name,
    found: hasExactMatch(values, requirement),
  }));
}

export function calculateCompatibility({ candidate, vacancy, criteria, desirables = [], addedValues = [], scoringVersion }) {
  if (!candidate || !vacancy || !Array.isArray(criteria) || scoringVersion == null) {
    throw new Error("SCORING_INPUT_INVALID");
  }

  const candidateYears = candidateExperienceYears(candidate);
  const experienceCriterion = criteria.find((criterion) => normalize(criterion.criterion_type) === "experiencia");
  const fallbackExperienceYears = experienceCriterion ? requiredExperienceYears(experienceCriterion, vacancy) : 0;
  let rawScore = 0;
  const mandatoryMissing = [];
  const criteriaResult = criteria
    .slice()
    .sort((left, right) => Number(left.evaluation_order ?? 0) - Number(right.evaluation_order ?? 0))
    .map((criterion) => {
      const type = normalize(criterion.criterion_type);
      const weight = Math.max(0, Number(criterion.weight) || 0);
      let matched;
      let points;
      let workEvidence = false;
      let explanation;

      if (type === "experiencia") {
        const requiredYears = requiredExperienceYears(criterion, vacancy);
        matched = requiredYears === 0 || candidateYears >= requiredYears;
        points = requiredYears === 0 ? weight : Math.min(candidateYears / requiredYears, 1) * weight;
        explanation = `Experiencia ${candidateYears} de ${requiredYears} años requeridos`;
      } else if (type === "educacion") {
        const requiredLevel = requiredEducationLevel(criterion, vacancy);
        const candidateLevel = candidateEducationLevel(candidate);
        matched = candidateLevel >= EDUCATION_LEVELS.indexOf(requiredLevel);
        points = matched ? weight : 0;
        explanation = `Educación ${requiredLevel}`;
      } else {
        matched = hasExactMatch(textValues(candidate), criterion);
        points = matched ? weight : 0;
        workEvidence = hasWorkEvidence(candidate, criterion);
        explanation = matched ? "Coincidencia exacta o alias configurado" : "Sin coincidencia exacta configurada";
      }

      points = Math.min(weight, Math.max(0, points));
      rawScore += points;
      if (criterion.is_required === true && !matched) mandatoryMissing.push(criterion.name);
      return {
        criterion: criterion.name,
        criterion_id: criterion.id,
        weight,
        points: Number(points.toFixed(2)),
        matched,
        mandatory: criterion.is_required === true,
        work_evidence: workEvidence,
        explanation,
      };
    });

  const score = Number(Math.min(100, Math.max(0, rawScore)).toFixed(2));
  const priority = score >= 80 ? "ALTA" : score >= 60 ? "MEDIA" : "BAJA";
  const desired = collectConfiguredMatches(candidate, desirables);
  const added = collectConfiguredMatches(candidate, addedValues);

  return {
    score,
    priority,
    scoring_version: Number(scoringVersion),
    criteria: criteriaResult,
    mandatory_missing: mandatoryMissing,
    desired_found: desired.filter((item) => item.found).map((item) => item.name),
    desired_missing: desired.filter((item) => !item.found).map((item) => item.name),
    added_value: added.filter((item) => item.found).map((item) => item.name),
    added_value_missing: added.filter((item) => !item.found).map((item) => item.name),
    seniority_fit: calculateSeniorityFit(candidateYears, vacancy, fallbackExperienceYears),
  };
}

export { EDUCATION_LEVELS };
