import { StrictMode, useEffect, useMemo, useState } from "react";
import { createRoot } from "react-dom/client";
import {
  BarChart3,
  BriefcaseBusiness,
  Check,
  ChevronLeft,
  ChevronRight,
  ClipboardCheck,
  Copy,
  FileSearch,
  LayoutDashboard,
  Menu,
  Pause,
  Plus,
  RotateCcw,
  Save,
  Settings,
  Users,
  X,
} from "lucide-react";
import "./styles.css";

const API_BASE_PATH = "/api";

type Criterion = {
  id: string;
  type: string;
  name: string;
  description: string;
  weight: number;
  required: boolean;
  aliases: string[];
  order: number;
};
type Extra = {
  id: string;
  name: string;
  description: string;
  relevance: string;
  type?: string;
  order: number;
};
type VacancyForm = Record<
  string,
  | string
  | number
  | boolean
  | Criterion[]
  | Extra[]
  | { id: string; name: string; order: number }[]
>;
type VacancyRow = {
  id: string;
  code: string;
  title: string;
  department?: string;
  seniority_level?: string;
  work_mode?: string;
  status: string;
  closes_at?: string;
  openings: number;
  application_count: number;
  active_scoring_version?: number;
};

type ValidationRequirement = {
  valid: boolean;
  label: string;
  step: number;
};

type PublicVacancy = {
  id: string;
  code: string;
  title: string;
  description?: string;
  department?: string;
  location?: string;
  workMode?: string;
  contractType?: string;
  seniorityLevel?: string;
  openings?: number;
  workday?: string;
  schedule?: string;
  salaryMin?: number | string;
  salaryMax?: number | string;
  salaryCurrency?: string;
  salaryPeriod?: string;
  showSalaryPublicly?: boolean;
  plannedPublishAt?: string;
  closesAt?: string;
  expectedStartDate?: string;
  minimumExperienceMonths?: number;
  minimumEducation?: string;
  relatedAcademicArea?: string;
  benefits?: Array<{ name: string; description?: string }>; 
  requirements?: Array<{ name: string; description?: string; required?: boolean; type?: string }>;
  desirables?: Array<{ name: string; description?: string }>;
  educationRequired?: boolean;
};

function normalizePublicVacancy(source: any): PublicVacancy | null {
  const vacancy = source?.vacancy ?? source;
  if (!vacancy?.id) return null;

  return {
    id: vacancy.id,
    code: vacancy.code ?? "",
    title: vacancy.title ?? "",
    description: vacancy.description ?? "",
    department: vacancy.department ?? "",
    location: vacancy.location ?? "",
    workMode: vacancy.workMode ?? vacancy.work_mode ?? "",
    contractType: vacancy.contractType ?? vacancy.contract_type ?? "",
    seniorityLevel: vacancy.seniorityLevel ?? vacancy.seniority_level ?? "",
    openings: vacancy.openings ?? 1,
    workday: vacancy.workday ?? "",
    schedule: vacancy.schedule ?? "",
    salaryMin: vacancy.salaryMin ?? vacancy.salary_min,
    salaryMax: vacancy.salaryMax ?? vacancy.salary_max,
    salaryCurrency: vacancy.salaryCurrency ?? vacancy.salary_currency ?? "COP",
    salaryPeriod: vacancy.salaryPeriod ?? vacancy.salary_period ?? "MONTH",
    showSalaryPublicly:
      vacancy.showSalaryPublicly ?? vacancy.show_salary_publicly ?? false,
    plannedPublishAt:
      vacancy.plannedPublishAt ?? vacancy.planned_publish_at ?? "",
    closesAt: vacancy.closesAt ?? vacancy.closes_at ?? "",
    expectedStartDate:
      vacancy.expectedStartDate ?? vacancy.expected_start_date ?? "",
    minimumExperienceMonths:
      vacancy.minimumExperienceMonths ?? vacancy.minimum_experience_months,
    minimumEducation:
      vacancy.minimumEducation ?? vacancy.minimum_education ?? "NONE",
    relatedAcademicArea:
      vacancy.relatedAcademicArea ?? vacancy.related_academic_area ?? "",
    benefits: source?.benefits ?? vacancy.benefits ?? [],
    requirements: source?.requirements ?? vacancy.requirements ?? [],
    desirables: source?.desirables ?? vacancy.desirables ?? [],
    educationRequired: vacancy.educationRequired ?? vacancy.education_required ?? false,
  };
}

const uid = () => crypto.randomUUID();
const emptyForm = (): VacancyForm => ({
  id: "",
  title: "",
  code: "",
  department: "",
  description: "",
  workMode: "REMOTE",
  location: "",
  contractType: "",
  seniorityLevel: "JUNIOR",
  openings: 1,
  workday: "",
  schedule: "",
  salaryMin: "",
  salaryMax: "",
  salaryCurrency: "COP",
  salaryPeriod: "MONTH",
  showSalaryPublicly: false,
  plannedPublishAt: "",
  closesAt: "",
  expectedStartDate: "",
  responsibleHrUserId: "10000000-0000-4000-8000-000000000001",
  minimumExperienceMonths: "",
  expectedExperienceMinMonths: "",
  expectedExperienceMaxMonths: "",
  minimumEducation: "NONE",
  relatedAcademicArea: "",
  educationRequired: false,
  educationAffectsScore: false,
  benefits: [],
  criteria: [],
  desirables: [],
  addedValues: [],
});

const labels: Record<string, string> = {
  DRAFT: "Borrador",
  OPEN: "Abierta",
  PAUSED: "Pausada",
  CLOSED: "Cerrada",
  COMPLETED: "Finalizada",
  REMOTE: "Remoto",
  ONSITE: "Presencial",
  HYBRID: "Hibrido",
};
const steps = [
  "Informacion general",
  "Perfil requerido",
  "Configuracion del score",
  "Deseables y valor agregado",
  "Vista previa",
  "Publicacion",
];

async function request(path: string, options?: RequestInit) {
  const headers = options?.body && !(options.body instanceof FormData)
    ? { "Content-Type": "application/json", ...options.headers }
    : options?.headers;
  const response = await fetch(`${API_BASE_PATH}${path}`, {
    ...options,
    headers,
  });
  const body = await response.json().catch(() => ({}));
  if (!response.ok || body.error)
    throw new Error(
      body.message || body.error || "No fue posible completar la operacion",
    );

  const payload = body.data ?? body;
  if (
    payload &&
    typeof payload === "object" &&
    "data" in payload &&
    !Array.isArray(payload) &&
    !("vacancy" in payload)
  ) {
    return payload.data;
  }

  return payload;
}

function navigate(path: string) {
  history.pushState({}, "", path);
  window.dispatchEvent(new PopStateEvent("popstate"));
}

function AdminLayout({ children }: { children: React.ReactNode }) {
  const [open, setOpen] = useState(false);
  const nav = [
    ["/admin/dashboard", "Dashboard", LayoutDashboard],
    ["/admin/vacantes", "Vacantes", BriefcaseBusiness],
    ["/admin/candidatos", "Candidatos", Users],
    ["/admin/revision", "Revision documental", FileSearch],
    ["/admin/metricas", "Metricas", BarChart3],
    ["/admin/configuracion", "Configuracion", Settings],
  ] as const;
  return (
    <div className="admin-shell">
      <aside className={open ? "sidebar open" : "sidebar"}>
        <div className="brand-row">
          <a
            href="/"
            aria-label="Ir al inicio publico de TalentFlow"
            title="Ir al portal de vacantes"
            onClick={(e) => {
              e.preventDefault();
              navigate("/");
              setOpen(false);
            }}
          >
            TalentFlow
          </a>
          <button
            className="icon-button mobile-only"
            onClick={() => setOpen(false)}
            aria-label="Cerrar menu"
          >
            <X />
          </button>
        </div>
        <p className="workspace-label">Gestion de talento</p>
        <nav>
          {nav.map(([path, label, Icon]) => (
            <a
              key={path}
              href={path}
              className={location.pathname.startsWith(path) ? "active" : ""}
              onClick={(e) => {
                e.preventDefault();
                navigate(path);
                setOpen(false);
              }}
            >
              <Icon />
              {label}
            </a>
          ))}
        </nav>
        <div className="user-block">
          <span>UD</span>
          <div>
            <strong>Usuario RRHH</strong>
            <small>Administrador</small>
          </div>
        </div>
      </aside>
      <section className="admin-main">
        <header className="topbar">
          <button
            className="icon-button mobile-only"
            onClick={() => setOpen(true)}
            aria-label="Abrir menu"
          >
            <Menu />
          </button>
          <div>
            <strong>Panel administrativo</strong>
            <small>TalentFlow</small>
          </div>
          <span className="env-badge">Entorno local</span>
        </header>
        <main>{children}</main>
      </section>
    </div>
  );
}

function Dashboard() {
  return (
    <>
      <PageTitle
        title="Dashboard"
        subtitle="Resumen operativo del equipo de Recursos Humanos"
      />
      <div className="metric-grid">
        <Metric label="Vacantes activas" value="--" />
        <Metric label="En revision" value="--" />
        <Metric label="Candidatos" value="--" />
      </div>
      <section className="panel empty-state">
        <BarChart3 />
        <h2>Metricas en preparacion</h2>
        <p>
          Los indicadores completos se habilitaran en el modulo correspondiente.
        </p>
      </section>
    </>
  );
}
function Metric({ label, value }: { label: string; value: string }) {
  return (
    <div className="metric">
      <span>{label}</span>
      <strong>{value}</strong>
    </div>
  );
}
function PageTitle({
  title,
  subtitle,
  action,
}: {
  title: string;
  subtitle: string;
  action?: React.ReactNode;
}) {
  return (
    <div className="page-title">
      <div>
        <h1>{title}</h1>
        <p>{subtitle}</p>
      </div>
      {action}
    </div>
  );
}
function Placeholder({ title }: { title: string }) {
  return (
    <>
      <PageTitle
        title={title}
        subtitle="Seccion prevista en la arquitectura de TalentFlow"
      />
      <section className="panel empty-state">
        <ClipboardCheck />
        <h2>Disponible en un modulo posterior</h2>
      </section>
    </>
  );
}

function VacancyList() {
  const [rows, setRows] = useState<VacancyRow[]>([]),
    [loading, setLoading] = useState(true),
    [error, setError] = useState("");
  const load = () => {
    setLoading(true);
    request("/admin/vacancies")
      .then((result) => setRows(Array.isArray(result) ? result : []))
      .catch((e) => setError(e.message))
      .finally(() => setLoading(false));
  };
  useEffect(load, []);
  const action = async (id: string, type: string) => {
    try {
      if (type === "duplicate") {
        const code = prompt("Nuevo codigo para la vacante duplicada");
        if (!code) return;
        await request(`/tf-admin-duplicate-vacancy/admin/vacancies/${id}/duplicate`, {
          method: "POST",
          body: JSON.stringify({ code }),
        });
      } else
        await request(`/tf-admin-status-vacancy/admin/vacancies/${id}/status`, {
          method: "POST",
          body: JSON.stringify({ status: type }),
        });
      load();
    } catch (e) {
      setError((e as Error).message);
    }
  };
  return (
    <>
      <PageTitle
        title="Vacantes"
        subtitle="Crea, publica y administra las oportunidades de la organizacion"
        action={
          <button
            className="primary"
            onClick={() => navigate("/admin/vacantes/nueva")}
          >
            <Plus />
            Nueva vacante
          </button>
        }
      />
      {error && <div className="alert error">{error}</div>}
      <section className="panel table-panel">
        {loading ? (
          <p className="loading">Cargando vacantes...</p>
        ) : (
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>Vacante</th>
                  <th>Area / nivel</th>
                  <th>Modalidad</th>
                  <th>Estado</th>
                  <th>Cierre</th>
                  <th>Plazas</th>
                  <th>Candidatos</th>
                  <th>Score</th>
                  <th>Acciones</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((v) => (
                  <tr key={v.id}>
                    <td>
                      <strong>{v.title}</strong>
                      <small>{v.code}</small>
                    </td>
                    <td>
                      {v.department || "Sin area"}
                      <small>{v.seniority_level || "Sin nivel"}</small>
                    </td>
                    <td>{labels[v.work_mode || ""] || "--"}</td>
                    <td>
                      <span className={`state ${v.status.toLowerCase()}`}>
                        {labels[v.status] || v.status}
                      </span>
                    </td>
                    <td>
                      {v.closes_at
                        ? new Date(v.closes_at).toLocaleDateString("es-CO")
                        : "--"}
                    </td>
                    <td>{v.openings}</td>
                    <td>{v.application_count}</td>
                    <td>
                      {v.active_scoring_version
                        ? `v${v.active_scoring_version}`
                        : "Borrador"}
                    </td>
                    <td>
                      <div className="row-actions">
                        <button
                          title="Ver o editar"
                          onClick={() => navigate(`/admin/vacantes/${v.id}`)}
                        >
                          <FileSearch />
                        </button>
                        <button
                          title="Duplicar"
                          onClick={() => action(v.id, "duplicate")}
                        >
                          <Copy />
                        </button>
                        {v.status === "OPEN" && (
                          <button
                            title="Pausar"
                            onClick={() => action(v.id, "PAUSED")}
                          >
                            <Pause />
                          </button>
                        )}
                        {v.status === "PAUSED" && (
                          <button
                            title="Reabrir"
                            onClick={() => action(v.id, "OPEN")}
                          >
                            <RotateCcw />
                          </button>
                        )}
                        {!["CLOSED", "COMPLETED"].includes(v.status) && (
                          <button
                            title="Cerrar"
                            onClick={() => action(v.id, "CLOSED")}
                          >
                            <X />
                          </button>
                        )}
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
            {!rows.length && (
              <div className="empty-state">
                <BriefcaseBusiness />
                <h2>No hay vacantes</h2>
                <p>Crea la primera vacante para comenzar.</p>
              </div>
            )}
          </div>
        )}
      </section>
    </>
  );
}

const Field = ({
  label,
  children,
  wide = false,
}: {
  label: string;
  children: React.ReactNode;
  wide?: boolean;
}) => (
  <label className={wide ? "field wide" : "field"}>
    <span>{label}</span>
    {children}
  </label>
);
const Input = ({
  form,
  setForm,
  name,
  type = "text",
  ...rest
}: {
  form: VacancyForm;
  setForm: (v: VacancyForm) => void;
  name: string;
  type?: string;
  [key: string]: unknown;
}) => (
  <input
    type={type}
    value={String(form[name] ?? "")}
    onChange={(e) =>
      setForm({
        ...form,
        [name]:
          type === "number"
            ? e.target.value === ""
              ? ""
              : Number(e.target.value)
            : e.target.value,
      })
    }
    {...rest}
  />
);
const Select = ({
  form,
  setForm,
  name,
  options,
}: {
  form: VacancyForm;
  setForm: (v: VacancyForm) => void;
  name: string;
  options: [string, string][];
}) => (
  <select
    value={String(form[name])}
    onChange={(e) => setForm({ ...form, [name]: e.target.value })}
  >
    {options.map(([v, l]) => (
      <option value={v} key={v}>
        {l}
      </option>
    ))}
  </select>
);

function Wizard({ id }: { id?: string }) {
  const [form, setForm] = useState(emptyForm()),
    [step, setStep] = useState(0),
    [saving, setSaving] = useState(false),
    [hasPublishedScoring, setHasPublishedScoring] = useState(false),
    [message, setMessage] = useState(""),
    [error, setError] = useState("");
  const criteria = form.criteria as Criterion[],
    total = criteria.reduce(
      (sum, c) => sum + (Number.isFinite(c.weight) ? c.weight : 0),
      0,
    );
  const salaryInvalid =
    Number(form.salaryMin) > Number(form.salaryMax) &&
    form.salaryMin !== "" &&
    form.salaryMax !== "";
  const datesInvalid = Boolean(
    form.plannedPublishAt &&
    form.closesAt &&
    String(form.closesAt) <= String(form.plannedPublishAt),
  );
  const experienceInvalid = Boolean(
    (form.minimumExperienceMonths !== "" &&
      Number(form.minimumExperienceMonths) < 0) ||
      (form.expectedExperienceMinMonths !== "" &&
        Number(form.expectedExperienceMinMonths) < 0) ||
      (form.expectedExperienceMaxMonths !== "" &&
        Number(form.expectedExperienceMaxMonths) < 0) ||
      (form.expectedExperienceMinMonths !== "" &&
        form.expectedExperienceMaxMonths !== "" &&
        Number(form.expectedExperienceMinMonths) >
          Number(form.expectedExperienceMaxMonths)),
  );
  const normalizedCriterionNames = criteria.map((criterion) =>
    criterion.name.trim().toLocaleLowerCase(),
  );
  const criteriaInvalid =
    normalizedCriterionNames.some((name) => !name) ||
    new Set(normalizedCriterionNames).size !== normalizedCriterionNames.length ||
    criteria.some(
      (criterion) =>
        !Number.isFinite(criterion.weight) ||
        criterion.weight < 0 ||
        criterion.weight > 100,
    );
  const minimumRequirements: ValidationRequirement[] = [
    { valid: Boolean(String(form.title).trim()), label: "Nombre de la vacante", step: 0 },
    { valid: Boolean(String(form.code).trim()), label: "Código único", step: 0 },
    { valid: Boolean(String(form.department).trim()), label: "Área o departamento", step: 0 },
    { valid: Boolean(form.workMode), label: "Modalidad", step: 0 },
    { valid: Boolean(form.seniorityLevel), label: "Nivel", step: 0 },
    { valid: Number(form.openings) > 0, label: "Número de plazas mayor que cero", step: 0 },
    { valid: !salaryInvalid, label: "Rango salarial válido", step: 0 },
    { valid: !datesInvalid, label: "Orden de fechas válido", step: 0 },
    { valid: !experienceInvalid, label: "Rango de experiencia válido", step: 1 },
  ];
  const minimumValid = minimumRequirements.every((requirement) => requirement.valid);
  const publishValid =
    minimumValid &&
    Boolean(form.closesAt) &&
    criteria.length > 0 &&
    !criteriaInvalid &&
    total === 100;
  useEffect(() => {
    if (id)
      request(`/tf-admin-get-vacancy/admin/vacancies/${id}`)
        .then((data) => {
          const v = data.vacancy,
            s = data.scoring || {};
          setHasPublishedScoring(s.status === "PUBLISHED");
          setForm({
            ...emptyForm(),
            ...v,
            id: v.id,
            workMode: v.work_mode || "",
            contractType: v.contract_type || "",
            seniorityLevel: v.seniority_level || "",
            salaryMin: v.salary_min || "",
            salaryMax: v.salary_max || "",
            salaryCurrency: v.salary_currency || "COP",
            salaryPeriod: v.salary_period || "MONTH",
            showSalaryPublicly: v.show_salary_publicly,
            plannedPublishAt: v.planned_publish_at?.slice(0, 16) || "",
            closesAt: v.closes_at?.slice(0, 16) || "",
            expectedStartDate: v.expected_start_date || "",
            responsibleHrUserId: v.responsible_hr_user_id,
            minimumExperienceMonths: v.minimum_experience_months ?? "",
            expectedExperienceMinMonths: v.expected_experience_min_months ?? "",
            expectedExperienceMaxMonths: v.expected_experience_max_months ?? "",
            minimumEducation: v.minimum_education,
            relatedAcademicArea: v.related_academic_area || "",
            educationRequired: v.education_required,
            educationAffectsScore: v.education_affects_score,
            benefits: data.benefits || [],
            criteria: (s.criteria || []).map((c: any) => ({
              ...c,
              type: c.criterion_type,
              required: c.is_required,
              order: c.evaluation_order,
            })),
            desirables: s.desirables || [],
            addedValues: (s.addedValues || []).map((x: any) => ({
              ...x,
              type: x.requirement_type,
            })),
          });
        })
        .catch((e) => setError(e.message));
  }, [id]);
  const save = async (publish = false) => {
    setSaving(true);
    setError("");
    setMessage("");
    try {
      let vacancyId = String(form.id || "");

      if (publish && !vacancyId) {
        const draftResult = await request("/admin/vacancies", {
          method: "POST",
          body: JSON.stringify(form),
        });
        vacancyId = String((draftResult.vacancy || draftResult).id);
      }

      const path = publish
        ? `/tf-admin-publish-vacancy/admin/vacancies/${vacancyId}/publish`
        : vacancyId
          ? `/tf-admin-update-vacancy/admin/vacancies/${vacancyId}`
          : "/admin/vacancies";
      const result = await request(path, {
        method: vacancyId && !publish ? "PUT" : "POST",
        body: JSON.stringify({ ...form, id: vacancyId }),
      });
      const saved = result.vacancy || result;
      setForm({ ...form, id: saved.id });
      setMessage(
        publish
          ? "Vacante publicada correctamente"
          : "Borrador guardado correctamente",
      );
      if (publish) setTimeout(() => navigate("/admin/vacantes"), 900);
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setSaving(false);
    }
  };
  return (
    <>
      <PageTitle
        title={id ? "Editar vacante" : "Nueva vacante"}
        subtitle={
          id
            ? "Los cambios de scoring publicados crean una nueva version"
            : "Completa los seis pasos para publicar una oportunidad"
        }
      />
      <div className="wizard-progress">
        {steps.map((name, i) => (
          <button
            className={i === step ? "current" : i < step ? "done" : ""}
            onClick={() => setStep(i)}
            key={name}
          >
            <span>{i < step ? <Check /> : i + 1}</span>
            <small>{name}</small>
          </button>
        ))}
      </div>
      {error && <div className="alert error">{error}</div>}
      {message && <div className="alert success">{message}</div>}
      {hasPublishedScoring && (
        <div className="alert warning">
          Modificar los criterios creará una nueva versión de scoring. La
          versión publicada se conservará para mantener la trazabilidad.
        </div>
      )}
      <section className="panel wizard-panel">
        {step === 0 && (
          <General
            form={form}
            setForm={setForm}
            salaryInvalid={salaryInvalid}
            datesInvalid={datesInvalid}
            requirements={minimumRequirements.filter(
              (requirement) => requirement.step === 0,
            )}
          />
        )}{" "}
        {step === 1 && (
          <Profile
            form={form}
            setForm={setForm}
            experienceInvalid={experienceInvalid}
            requirements={minimumRequirements.filter(
              (requirement) => requirement.step === 1,
            )}
          />
        )}{" "}
        {step === 2 && (
          <Score
            form={form}
            setForm={setForm}
            total={total}
            criteriaInvalid={criteriaInvalid}
          />
        )}{" "}
        {step === 3 && <Extras form={form} setForm={setForm} />}{" "}
        {step === 4 && <Preview form={form} total={total} />}{" "}
        {step === 5 && (
          <Publish
            total={total}
            criteriaCount={criteria.length}
            criteriaValid={!criteriaInvalid}
            hasClosingDate={Boolean(form.closesAt)}
            minimumRequirements={minimumRequirements}
            onGoToStep={setStep}
          />
        )}
        <div className="wizard-actions">
          <button
            className="secondary"
            disabled={step === 0}
            onClick={() => setStep(step - 1)}
          >
            <ChevronLeft />
            Anterior
          </button>
          <div>
            <button
              className="secondary"
              disabled={saving}
              onClick={() => save(false)}
            >
              <Save />
              Guardar borrador
            </button>
            {step < 5 ? (
              <button className="primary" onClick={() => setStep(step + 1)}>
                Continuar
                <ChevronRight />
              </button>
            ) : (
              <button
                className="primary"
                disabled={!publishValid || saving}
                onClick={() => save(true)}
              >
                <Check />
                Publicar vacante
              </button>
            )}
          </div>
        </div>
      </section>
    </>
  );
}

function ValidationSummary({
  requirements,
}: {
  requirements: ValidationRequirement[];
}) {
  const missing = requirements.filter((requirement) => !requirement.valid);

  if (!missing.length) {
    return <div className="alert success validation-summary">Sección completa.</div>;
  }

  return (
    <div className="alert warning validation-summary">
      <strong>Falta completar o corregir:</strong>
      <ul>
        {missing.map((requirement) => (
          <li key={requirement.label}>{requirement.label}</li>
        ))}
      </ul>
    </div>
  );
}

function General({
  form,
  setForm,
  salaryInvalid,
  datesInvalid,
  requirements,
}: {
  form: VacancyForm;
  setForm: (v: VacancyForm) => void;
  salaryInvalid: boolean;
  datesInvalid: boolean;
  requirements: ValidationRequirement[];
}) {
  const benefits = form.benefits as any[];
  return (
    <>
      <SectionTitle
        n="01"
        title="Informacion general"
        text="Datos publicos y condiciones de la oportunidad"
      />
      <ValidationSummary requirements={requirements} />
      <div className="form-grid">
        <Field label="Nombre de la vacante">
          <Input form={form} setForm={setForm} name="title" required />
        </Field>
        <Field label="Codigo unico">
          <Input
            form={form}
            setForm={setForm}
            name="code"
            placeholder="BACK-JR-01"
          />
        </Field>
        <Field label="Area o departamento">
          <Input form={form} setForm={setForm} name="department" />
        </Field>
        <Field label="Modalidad">
          <Select
            form={form}
            setForm={setForm}
            name="workMode"
            options={[
              ["ONSITE", "Presencial"],
              ["REMOTE", "Remoto"],
              ["HYBRID", "Hibrido"],
            ]}
          />
        </Field>
        <Field label="Descripcion" wide>
          <textarea
            value={String(form.description)}
            onChange={(e) => setForm({ ...form, description: e.target.value })}
          />
        </Field>
        <Field label="Ubicacion">
          <Input form={form} setForm={setForm} name="location" />
        </Field>
        <Field label="Tipo de contrato">
          <Input form={form} setForm={setForm} name="contractType" />
        </Field>
        <Field label="Nivel">
          <Select
            form={form}
            setForm={setForm}
            name="seniorityLevel"
            options={[
              ["INTERN", "Practicante"],
              ["JUNIOR", "Junior"],
              ["MID", "Mid"],
              ["SENIOR", "Senior"],
              ["LEAD", "Lead"],
              ["OTHER", "Otro"],
            ]}
          />
        </Field>
        <Field label="Numero de plazas">
          <Input
            form={form}
            setForm={setForm}
            name="openings"
            type="number"
            min={1}
          />
        </Field>
        <Field label="Jornada">
          <Input form={form} setForm={setForm} name="workday" />
        </Field>
        <Field label="Horario">
          <Input form={form} setForm={setForm} name="schedule" />
        </Field>
      </div>
      <h3>Compensacion</h3>
      <div className="form-grid">
        <Field label="Salario minimo">
          <Input
            form={form}
            setForm={setForm}
            name="salaryMin"
            type="number"
            min={0}
          />
        </Field>
        <Field label="Salario maximo">
          <Input
            form={form}
            setForm={setForm}
            name="salaryMax"
            type="number"
            min={0}
          />
        </Field>
        <Field label="Moneda">
          <Input
            form={form}
            setForm={setForm}
            name="salaryCurrency"
            maxLength={3}
          />
        </Field>
        <Field label="Periodicidad">
          <Select
            form={form}
            setForm={setForm}
            name="salaryPeriod"
            options={[
              ["HOUR", "Hora"],
              ["DAY", "Dia"],
              ["WEEK", "Semana"],
              ["MONTH", "Mes"],
              ["YEAR", "Ano"],
            ]}
          />
        </Field>
        {salaryInvalid && (
          <p className="validation-error wide">
            El salario minimo no puede superar al maximo.
          </p>
        )}
        <label className="check wide">
          <input
            type="checkbox"
            checked={Boolean(form.showSalaryPublicly)}
            onChange={(e) =>
              setForm({ ...form, showSalaryPublicly: e.target.checked })
            }
          />
          Mostrar salario publicamente
        </label>
      </div>
      <h3>Fechas</h3>
      <div className="form-grid">
        <Field label="Publicacion prevista">
          <Input
            form={form}
            setForm={setForm}
            name="plannedPublishAt"
            type="datetime-local"
          />
        </Field>
        <Field label="Fecha de cierre">
          <Input
            form={form}
            setForm={setForm}
            name="closesAt"
            type="datetime-local"
          />
        </Field>
        <Field label="Ingreso estimado">
          <Input
            form={form}
            setForm={setForm}
            name="expectedStartDate"
            type="date"
          />
        </Field>
        {datesInvalid && (
          <p className="validation-error wide">
            La fecha de cierre debe ser posterior a la publicacion.
          </p>
        )}
      </div>
      <DynamicSimple
        title="Beneficios"
        items={benefits}
        onChange={(items) => setForm({ ...form, benefits: items })}
        placeholder="Ej. Horario flexible"
      />
    </>
  );
}

function Profile({
  form,
  setForm,
  experienceInvalid,
  requirements,
}: {
  form: VacancyForm;
  setForm: (v: VacancyForm) => void;
  experienceInvalid: boolean;
  requirements: ValidationRequirement[];
}) {
  return (
    <>
      <SectionTitle
        n="02"
        title="Perfil requerido"
        text="Experiencia y educacion esperadas, sin penalizar experiencia superior"
      />
      <ValidationSummary requirements={requirements} />
      <h3>Experiencia en meses</h3>
      <div className="form-grid">
        <Field label="Experiencia minima">
          <Input
            form={form}
            setForm={setForm}
            name="minimumExperienceMonths"
            type="number"
            min={0}
          />
        </Field>
        <Field label="Rango esperado minimo">
          <Input
            form={form}
            setForm={setForm}
            name="expectedExperienceMinMonths"
            type="number"
            min={0}
          />
        </Field>
        <Field label="Rango esperado maximo">
          <Input
            form={form}
            setForm={setForm}
            name="expectedExperienceMaxMonths"
            type="number"
            min={0}
          />
        </Field>
        {experienceInvalid && (
          <p className="validation-error wide">
            La experiencia no puede ser negativa y el mínimo esperado no puede
            superar al máximo.
          </p>
        )}
      </div>
      <h3>Educacion</h3>
      <div className="form-grid">
        <Field label="Nivel minimo">
          <Select
            form={form}
            setForm={setForm}
            name="minimumEducation"
            options={[
              ["NONE", "Ninguna"],
              ["HIGH_SCHOOL", "Bachiller"],
              ["TECHNICAL", "Tecnico"],
              ["TECHNOLOGIST", "Tecnologo"],
              ["PROFESSIONAL", "Profesional"],
              ["SPECIALIZATION", "Especializacion"],
              ["MASTER", "Maestria"],
              ["DOCTORATE", "Doctorado"],
            ]}
          />
        </Field>
        <Field label="Area academica relacionada">
          <Input form={form} setForm={setForm} name="relatedAcademicArea" />
        </Field>
        <label className="check">
          <input
            type="checkbox"
            checked={Boolean(form.educationRequired)}
            onChange={(e) =>
              setForm({ ...form, educationRequired: e.target.checked })
            }
          />
          Educacion obligatoria
        </label>
        <label className="check">
          <input
            type="checkbox"
            checked={Boolean(form.educationAffectsScore)}
            onChange={(e) =>
              setForm({ ...form, educationAffectsScore: e.target.checked })
            }
          />
          Educacion afecta el score
        </label>
      </div>
    </>
  );
}

function Score({
  form,
  setForm,
  total,
  criteriaInvalid,
}: {
  form: VacancyForm;
  setForm: (v: VacancyForm) => void;
  total: number;
  criteriaInvalid: boolean;
}) {
  const items = form.criteria as Criterion[];
  const update = (id: string, key: keyof Criterion, value: any) =>
    setForm({
      ...form,
      criteria: items.map((x) => (x.id === id ? { ...x, [key]: value } : x)),
    });
  return (
    <>
      <SectionTitle
        n="03"
        title="Configuracion del score"
        text="Los criterios evaluables deben sumar exactamente 100 puntos"
      />
      <ScoreStatus total={total} />
      {criteriaInvalid && (
        <p className="validation-error">
          Cada criterio debe tener un nombre único y un peso entre 0 y 100.
        </p>
      )}
      <div className="item-list">
        {items.map((c, i) => (
          <div className="editable-item" key={c.id}>
            <div className="item-head">
              <strong>Criterio {i + 1}</strong>
              <button
                className="icon-button"
                onClick={() =>
                  setForm({
                    ...form,
                    criteria: items.filter((x) => x.id !== c.id),
                  })
                }
                aria-label="Eliminar"
              >
                <X />
              </button>
            </div>
            <div className="form-grid">
              <Field label="Tipo">
                <select
                  value={c.type ?? "OTRO"}
                  onChange={(e) => update(c.id, "type", e.target.value)}
                >
                  {[
                    "TECNOLOGIA",
                    "CONOCIMIENTO",
                    "EXPERIENCIA",
                    "EDUCACION",
                    "IDIOMA",
                    "COMPETENCIA_TECNICA",
                    "OTRO",
                  ].map((x) => (
                    <option key={x}>{x}</option>
                  ))}
                </select>
              </Field>
              <Field label="Nombre">
                <input
                  value={c.name ?? ""}
                  onChange={(e) => update(c.id, "name", e.target.value)}
                />
              </Field>
              <Field label="Peso">
                <input
                  type="number"
                  min="0"
                  max="100"
                  value={c.weight ?? ""}
                  onChange={(e) =>
                    update(
                      c.id,
                      "weight",
                      Math.max(0, Number(e.target.value) || 0),
                    )
                  }
                />
              </Field>
              <Field label="Aliases separados por coma">
                <input
                  value={(c.aliases ?? []).join(", ")}
                  onChange={(e) =>
                    update(
                      c.id,
                      "aliases",
                      e.target.value
                        .split(",")
                        .map((x) => x.trim())
                        .filter(Boolean),
                    )
                  }
                />
              </Field>
              <Field label="Descripcion" wide>
                <input
                  value={c.description ?? ""}
                  onChange={(e) => update(c.id, "description", e.target.value)}
                />
              </Field>
              <label className="check">
                <input
                  type="checkbox"
                  checked={c.required}
                  onChange={(e) => update(c.id, "required", e.target.checked)}
                />
                Requisito obligatorio
              </label>
            </div>
          </div>
        ))}
      </div>
      <button
        className="secondary"
        onClick={() =>
          setForm({
            ...form,
            criteria: [
              ...items,
              {
                id: uid(),
                type: "TECNOLOGIA",
                name: "",
                description: "",
                weight: 0,
                required: false,
                aliases: [],
                order: items.length,
              },
            ],
          })
        }
      >
        <Plus />
        Agregar criterio
      </button>
      <p className="muted">
        Un requisito obligatorio no produce descarte automatico. RRHH conserva
        la decision final.
      </p>
    </>
  );
}
function ScoreStatus({ total }: { total: number }) {
  const delta = 100 - total;
  return (
    <div className={`score-status ${total === 100 ? "valid" : "invalid"}`}>
      <div>
        <span>Puntos asignados</span>
        <strong>{total} / 100</strong>
      </div>
      <div className="score-track">
        <i style={{ width: `${Math.min(total, 100)}%` }} />
      </div>
      <p>
        {total === 100 ? (
          <>
            <Check />
            Configuracion valida
          </>
        ) : total < 100 ? (
          `Faltan ${delta} puntos por asignar`
        ) : (
          `Excedes el maximo por ${Math.abs(delta)} puntos`
        )}
      </p>
    </div>
  );
}

function Extras({
  form,
  setForm,
}: {
  form: VacancyForm;
  setForm: (v: VacancyForm) => void;
}) {
  return (
    <>
      <SectionTitle
        n="04"
        title="Deseables y valor agregado"
        text="Informacion complementaria que no altera los 100 puntos"
      />
      <DynamicExtras
        title="Requisitos deseables"
        items={form.desirables as Extra[]}
        onChange={(x) => setForm({ ...form, desirables: x })}
      />
      <DynamicExtras
        title="Valor agregado"
        withType
        items={form.addedValues as Extra[]}
        onChange={(x) => setForm({ ...form, addedValues: x })}
      />
    </>
  );
}
function DynamicSimple({
  title,
  items,
  onChange,
  placeholder,
}: {
  title: string;
  items: any[];
  onChange: (x: any[]) => void;
  placeholder: string;
}) {
  return (
    <div className="dynamic-block">
      <div className="block-title">
        <h3>{title}</h3>
        <button
          className="secondary small"
          onClick={() =>
            onChange([...items, { id: uid(), name: "", order: items.length }])
          }
        >
          <Plus />
          Agregar
        </button>
      </div>
      {items.map((x) => (
        <div className="inline-row" key={x.id}>
          <input
            placeholder={placeholder}
            value={x.name ?? ""}
            onChange={(e) =>
              onChange(
                items.map((i) =>
                  i.id === x.id ? { ...i, name: e.target.value } : i,
                ),
              )
            }
          />
          <button
            className="icon-button"
            onClick={() => onChange(items.filter((i) => i.id !== x.id))}
          >
            <X />
          </button>
        </div>
      ))}
    </div>
  );
}
function DynamicExtras({
  title,
  items,
  onChange,
  withType = false,
}: {
  title: string;
  items: Extra[];
  onChange: (x: Extra[]) => void;
  withType?: boolean;
}) {
  const update = (id: string, key: string, value: string) =>
    onChange(items.map((x) => (x.id === id ? { ...x, [key]: value } : x)));
  return (
    <div className="dynamic-block">
      <div className="block-title">
        <h3>{title}</h3>
        <button
          className="secondary small"
          onClick={() =>
            onChange([
              ...items,
              {
                id: uid(),
                name: "",
                description: "",
                relevance: "MEDIUM",
                type: withType ? "OTHER" : undefined,
                order: items.length,
              },
            ])
          }
        >
          <Plus />
          Agregar
        </button>
      </div>
      {items.map((x) => (
        <div className="editable-item compact" key={x.id}>
          <input
            placeholder="Nombre"
            value={x.name ?? ""}
            onChange={(e) => update(x.id, "name", e.target.value)}
          />
          <input
            placeholder="Descripcion opcional"
            value={x.description ?? ""}
            onChange={(e) => update(x.id, "description", e.target.value)}
          />
          {withType && (
            <select
              value={x.type ?? "OTHER"}
              onChange={(e) => update(x.id, "type", e.target.value)}
            >
              {[
                "COURSE",
                "CERTIFICATION",
                "PROJECT_MANAGEMENT",
                "SCRUM",
                "AI_USAGE",
                "ADDITIONAL_LANGUAGE",
                "OTHER",
              ].map((v) => (
                <option key={v}>{v}</option>
              ))}
            </select>
          )}
          <select
            value={x.relevance ?? "MEDIUM"}
            onChange={(e) => update(x.id, "relevance", e.target.value)}
          >
            <option value="LOW">Baja</option>
            <option value="MEDIUM">Media</option>
            <option value="HIGH">Alta</option>
          </select>
          <button
            className="icon-button"
            onClick={() => onChange(items.filter((i) => i.id !== x.id))}
          >
            <X />
          </button>
        </div>
      ))}
    </div>
  );
}
function Preview({ form, total }: { form: VacancyForm; total: number }) {
  return (
    <>
      <SectionTitle
        n="05"
        title="Vista previa"
        text="Revisa la configuracion completa antes de publicar"
      />
      <div className="preview-grid">
        <PreviewBlock
          title="Informacion general"
          lines={[
            String(form.title) || "Sin nombre",
            String(form.code) || "Sin codigo",
            `${form.department || "Sin area"} · ${labels[String(form.workMode)]}`,
            `${form.openings} plaza(s)`,
          ]}
        />
        <PreviewBlock
          title="Compensacion"
          lines={[
            form.salaryMin || form.salaryMax
              ? `${form.salaryMin || "--"} - ${form.salaryMax || "--"} ${form.salaryCurrency} / ${form.salaryPeriod}`
              : "No especificada",
            form.showSalaryPublicly ? "Visible publicamente" : "Uso interno",
          ]}
        />
        <PreviewBlock
          title="Perfil"
          lines={[
            `Experiencia minima: ${form.minimumExperienceMonths || 0} meses`,
            `Educacion: ${form.minimumEducation}`,
            form.educationRequired ? "Obligatoria" : "No obligatoria",
          ]}
        />
        <PreviewBlock
          title="Complementarios"
          lines={[
            `${(form.benefits as any[]).length} beneficios`,
            `${(form.desirables as any[]).length} deseables`,
            `${(form.addedValues as any[]).length} valores agregados`,
          ]}
        />
      </div>
      <h3>Criterios evaluables</h3>
      <div className="criteria-preview">
        {(form.criteria as Criterion[]).map((c) => (
          <div key={c.id}>
            <span>
              {c.name || "Sin nombre"}
              {c.required && <small>Obligatorio</small>}
            </span>
            <strong>{c.weight} pts</strong>
          </div>
        ))}
      </div>
      <ScoreStatus total={total} />
    </>
  );
}
function PreviewBlock({
  title,
  lines,
}: {
  title: string;
  lines: (string | number | boolean)[];
}) {
  return (
    <div className="preview-block">
      <h3>{title}</h3>
      {lines.map((x, i) => (
        <p key={i}>{String(x)}</p>
      ))}
    </div>
  );
}
function Publish({
  total,
  criteriaCount,
  criteriaValid,
  hasClosingDate,
  minimumRequirements,
  onGoToStep,
}: {
  total: number;
  criteriaCount: number;
  criteriaValid: boolean;
  hasClosingDate: boolean;
  minimumRequirements: ValidationRequirement[];
  onGoToStep: (step: number) => void;
}) {
  const checks: ValidationRequirement[] = [
    ...minimumRequirements,
    { valid: hasClosingDate, label: "Fecha de cierre definida", step: 0 },
    { valid: criteriaCount > 0, label: "Al menos un criterio evaluable", step: 2 },
    { valid: criteriaValid, label: "Criterios con nombres únicos y pesos válidos", step: 2 },
    { valid: total === 100, label: "Score asignado exactamente en 100 puntos", step: 2 },
  ];
  return (
    <>
      <SectionTitle
        n="06"
        title="Publicacion"
        text="La persistencia volvera a validar todas las reglas"
      />
      <div className="publish-checks">
        {checks.map((check) => (
          <div className={check.valid ? "ok" : "pending"} key={check.label}>
            {check.valid ? <Check /> : <X />}
            <span>{check.label}</span>
            {!check.valid && (
              <button className="validation-link" onClick={() => onGoToStep(check.step)}>
                Corregir
              </button>
            )}
          </div>
        ))}
      </div>
      {total !== 100 && (
        <div className="alert warning">
          La vacante puede guardarse como borrador, pero no puede publicarse con{" "}
          {total} puntos.
        </div>
      )}
    </>
  );
}
function SectionTitle({
  n,
  title,
  text,
}: {
  n: string;
  title: string;
  text: string;
}) {
  return (
    <div className="section-title">
      <span>{n}</span>
      <div>
        <h2>{title}</h2>
        <p>{text}</p>
      </div>
    </div>
  );
}

function formatCurrency(
  min?: number | string,
  max?: number | string,
  currency = "COP",
  period = "MONTH",
) {
  if (min === undefined && max === undefined) return "No especificado";
  const toNumber = (value: number | string | undefined) => {
    if (value === undefined || value === null || value === "") return null;
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : null;
  };

  const from = toNumber(min);
  const to = toNumber(max);
  const base = currency || "COP";
  const unit = period === "YEAR" ? "/año" : period === "MONTH" ? "/mes" : period === "WEEK" ? "/semana" : period === "DAY" ? "/día" : "/hora";

  if (from !== null && to !== null) {
    return `${from.toLocaleString("es-CO")} - ${to.toLocaleString("es-CO")} ${base}${unit}`;
  }
  if (from !== null) return `${from.toLocaleString("es-CO")} ${base}${unit}`;
  if (to !== null) return `Hasta ${to.toLocaleString("es-CO")} ${base}${unit}`;
  return "No especificado";
}

function formatDate(value?: string) {
  if (!value) return "--";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "--";
  return date.toLocaleDateString("es-CO", {
    day: "2-digit",
    month: "short",
    year: "numeric",
  });
}

function PublicLayout({ children }: { children: React.ReactNode }) {
  return (
    <div className="public-shell">
      <header className="public-header">
        <a
          className="public-brand"
          href="/"
          aria-label="Ir al inicio de TalentFlow"
          onClick={(e) => {
            e.preventDefault();
            navigate("/");
          }}
        >
          <span>TalentFlow</span>
          <small>Bolsa de talento</small>
        </a>
        <nav className="public-nav">
          <a href="/vacantes" onClick={(e) => { e.preventDefault(); navigate("/vacantes"); }}>
            Vacantes
          </a>
          <a href="/admin" onClick={(e) => { e.preventDefault(); navigate("/admin/dashboard"); }}>
            Panel RRHH
          </a>
        </nav>
      </header>
      <main className="public-main">{children}</main>
    </div>
  );
}

function VacancyCatalog() {
  const [vacancies, setVacancies] = useState<PublicVacancy[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");

  useEffect(() => {
    request("/public/vacancies")
      .then((result) =>
        setVacancies(
          Array.isArray(result)
            ? result
                .map(normalizePublicVacancy)
                .filter((vacancy): vacancy is PublicVacancy => vacancy !== null)
            : [],
        ),
      )
      .catch((e) => setError(e.message))
      .finally(() => setLoading(false));
  }, []);

  return (
    <PublicLayout>
      <div className="public-hero">
        <p className="eyebrow">Oportunidades abiertas</p>
        <h1>Encuentra la vacante ideal para tu perfil</h1>
        <p>
          Consulta solo las posiciones activas y aplica con tu hoja de vida en formato PDF.
        </p>
      </div>

      {error && <div className="alert error">{error}</div>}

      {loading ? (
        <div className="panel loading-box">Cargando vacantes...</div>
      ) : vacancies.length === 0 ? (
        <div className="panel empty-state">
          <BriefcaseBusiness />
          <h2>No hay vacantes abiertas en este momento</h2>
          <p>Vuelve pronto para ver nuevas oportunidades.</p>
        </div>
      ) : (
        <div className="vacancy-grid">
          {vacancies.map((vacancy) => (
            <article className="vacancy-card panel" key={vacancy.id}>
              <div className="card-head">
                <span className="tag">{vacancy.department || "General"}</span>
                <span className="tag muted-tag">{vacancy.workMode || "--"}</span>
              </div>
              <h2>{vacancy.title}</h2>
              <p className="meta-row">
                <span>{vacancy.location || "Remoto / Colombia"}</span>
                <span>{vacancy.contractType || "Contrato"}</span>
              </p>
              <p className="summary">
                {vacancy.description || "Vacante disponible para candidatos interesados en esta oportunidad."}
              </p>
              <ul className="facts-list">
                <li>Plazas: {vacancy.openings || 1}</li>
                <li>Nivel: {vacancy.seniorityLevel || "Indefinido"}</li>
                {vacancy.showSalaryPublicly && (
                  <li>
                    Salario: {formatCurrency(vacancy.salaryMin, vacancy.salaryMax, vacancy.salaryCurrency, vacancy.salaryPeriod)}
                  </li>
                )}
              </ul>
              <div className="card-footer">
                <small>Cierre: {formatDate(vacancy.closesAt)}</small>
                <button
                  className="primary"
                  onClick={() => navigate(`/vacantes/${vacancy.id}`)}
                >
                  Ver detalle
                </button>
              </div>
            </article>
          ))}
        </div>
      )}
    </PublicLayout>
  );
}

function VacancyDetail({ id }: { id: string }) {
  const [vacancy, setVacancy] = useState<PublicVacancy | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");

  useEffect(() => {
    request(`/tf-public-get-vacancy/public/vacancies/${id}`)
      .then(async (result) => {
        const publicVacancy = normalizePublicVacancy(result);
        if (publicVacancy) return publicVacancy;

        const adminResult = await request(
          `/tf-admin-get-vacancy/admin/vacancies/${id}`,
        );
        return normalizePublicVacancy(adminResult);
      })
      .then(setVacancy)
      .catch((e) => setError(e.message))
      .finally(() => setLoading(false));
  }, [id]);

  if (loading) return <PublicLayout><div className="panel loading-box">Cargando detalle...</div></PublicLayout>;
  if (error) return <PublicLayout><div className="alert error">{error}</div></PublicLayout>;
  if (!vacancy) {
    return (
      <PublicLayout>
        <div className="panel empty-state">
          <FileSearch />
          <h2>Vacante no encontrada</h2>
          <p>La oportunidad solicitada ya no está disponible.</p>
        </div>
      </PublicLayout>
    );
  }

  return (
    <PublicLayout>
      <div className="detail-shell">
        <div className="panel vacancy-detail">
          <p className="eyebrow">{vacancy.code}</p>
          <h1>{vacancy.title}</h1>
          <div className="detail-meta">
            <span>{vacancy.department || "Departamento"}</span>
            <span>{vacancy.location || "Remoto / Colombia"}</span>
            <span>{vacancy.workMode || "Modadlidad"}</span>
          </div>

          <div className="detail-grid">
            <div>
              <h3>Descripción</h3>
              <p>{vacancy.description || "Descripción no disponible."}</p>
            </div>
            <aside>
              <h3>Resumen</h3>
              <ul>
                <li>Tipo de contrato: {vacancy.contractType || "No especificado"}</li>
                <li>Nivel: {vacancy.seniorityLevel || "No especificado"}</li>
                <li>Plazas: {vacancy.openings || 1}</li>
                <li>Horario: {vacancy.workday || vacancy.schedule || "No especificado"}</li>
                <li>
                  Salario: {vacancy.showSalaryPublicly
                    ? formatCurrency(vacancy.salaryMin, vacancy.salaryMax, vacancy.salaryCurrency, vacancy.salaryPeriod)
                    : "No se comparte públicamente"}
                </li>
                <li>Cierre: {formatDate(vacancy.closesAt)}</li>
              </ul>
            </aside>
          </div>

          {Array.isArray(vacancy.benefits) && vacancy.benefits.length > 0 && (
            <div className="benefits-box">
              <h3>Beneficios</h3>
              <ul>
                {vacancy.benefits.map((item, index) => (
                  <li key={`${item.name}-${index}`}>{item.name}</li>
                ))}
              </ul>
            </div>
          )}

          {Array.isArray(vacancy.requirements) && vacancy.requirements.length > 0 && (
            <div className="benefits-box">
              <h3>Requisitos</h3>
              <ul>
                {vacancy.requirements.map((item, index) => (
                  <li key={`${item.name}-${index}`}>
                    <strong>{item.name}</strong>{item.description ? `: ${item.description}` : ""}
                    {item.required ? " (obligatorio)" : ""}
                  </li>
                ))}
              </ul>
            </div>
          )}

          <div className="detail-grid public-requirements">
            <div>
              <h3>Experiencia requerida</h3>
              <p>{vacancy.minimumExperienceMonths
                ? `${vacancy.minimumExperienceMonths} meses como mínimo`
                : "No se definió una experiencia mínima."}</p>
            </div>
            {vacancy.educationRequired && vacancy.minimumEducation !== "NONE" && (
              <div>
                <h3>Educación</h3>
                <p>{vacancy.minimumEducation}{vacancy.relatedAcademicArea ? ` — ${vacancy.relatedAcademicArea}` : ""}</p>
              </div>
            )}
          </div>

          {Array.isArray(vacancy.desirables) && vacancy.desirables.length > 0 && (
            <div className="benefits-box">
              <h3>Conocimientos deseables</h3>
              <ul>{vacancy.desirables.map((item, index) => (
                <li key={`${item.name}-${index}`}>{item.name}{item.description ? `: ${item.description}` : ""}</li>
              ))}</ul>
            </div>
          )}

          <div className="detail-actions">
            <button className="secondary" onClick={() => navigate("/vacantes")}>
              Volver
            </button>
            <button className="primary" onClick={() => navigate(`/postular/${vacancy.id}`)}>
              Postularme
            </button>
          </div>
        </div>
      </div>
    </PublicLayout>
  );
}

function ApplicationForm({ vacancyId }: { vacancyId: string }) {
  const [form, setForm] = useState({
    firstName: "",
    lastName: "",
    email: "",
    phone: "",
    experienceYears: "",
    skills: "",
    consentAccepted: false,
  });
  const [cvFile, setCvFile] = useState<File | null>(null);
  const [cvError, setCvError] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState("");
  const [success, setSuccess] = useState("");
  const [ticketId, setTicketId] = useState("");
  const [applicationId, setApplicationId] = useState("");
  const [attemptNumber, setAttemptNumber] = useState(0);
  const [canRequestManualReview, setCanRequestManualReview] = useState(false);
  const [requestingManualReview, setRequestingManualReview] = useState(false);

  const onFileChange = (file?: File) => {
    if (!file) {
      setCvFile(null);
      setCvError("Debes adjuntar tu hoja de vida en PDF.");
      return;
    }

    const isPdf = file.type === "application/pdf" || file.name.toLowerCase().endsWith(".pdf");
    if (!isPdf) {
      setCvFile(null);
      setCvError("El archivo debe ser un PDF válido.");
      return;
    }

    if (file.size > 5 * 1024 * 1024) {
      setCvFile(null);
      setCvError("El PDF no puede superar 5 MB.");
      return;
    }

    setCvFile(file);
    setCvError("");
  };

  const submit = async (event: React.FormEvent) => {
    event.preventDefault();
    setError("");
    setSuccess("");

    if (!form.consentAccepted) {
      setError("Debe aceptar el tratamiento de datos para continuar.");
      return;
    }

    const file = cvFile;
    if (!file) {
      setError("Debe adjuntar la hoja de vida en PDF.");
      return;
    }

    const isPdf = file.type === "application/pdf" || file.name.toLowerCase().endsWith(".pdf");
    if (!isPdf || file.size > 5 * 1024 * 1024) {
      setError("El archivo adjunto no cumple con el formato o tamaño permitido.");
      return;
    }

    setSubmitting(true);
    try {
      const payload = new FormData();
      payload.append("vacancyId", vacancyId);
      payload.append("firstName", form.firstName.trim());
      payload.append("lastName", form.lastName.trim());
      payload.append("email", form.email.trim());
      payload.append("phone", form.phone.trim());
      payload.append("experienceYears", form.experienceYears);
      payload.append("skills", form.skills);
      payload.append("consentAccepted", String(form.consentAccepted));
      payload.append("cv", file, file.name);

      const result = await request("/public/applications", {
        method: "POST",
        body: payload,
      });
      setTicketId(result.ticketId || "");
      setApplicationId(result.applicationId || "");
      setAttemptNumber(result.attemptNumber || 0);
      setCanRequestManualReview(Boolean(result.canRequestManualReview));
      if (result.status === "RECIBIDO") {
        setSuccess(`Tu postulación fue recibida correctamente. Ticket: ${result.ticketId}`);
      } else if (result.errorType === "SYSTEM_ERROR") {
        setError("No pudimos completar la validación por un problema interno. Tu CV no es el problema; intenta nuevamente más tarde.");
      } else {
        const attempt = Number(result.attemptNumber || 1);
        setError(attempt === 1
          ? "No pudimos leer correctamente el documento. Asegúrate de cargar un PDF que contenga texto seleccionable y no únicamente imágenes escaneadas."
          : attempt === 2
            ? "El documento continúa sin poder procesarse. Intenta exportar nuevamente tu hoja de vida desde Word, Google Docs u otra herramienta en formato PDF."
            : "No pudimos leer correctamente tu hoja de vida. Puedes cargar otra versión o enviarla para revisión manual.");
      }
    } catch (e: any) {
      const message = String(e?.message || "");
      setError(
        /resource you are requesting|file not found|google drive/i.test(message)
          ? "El PDF se leyó correctamente, pero no pudimos almacenarlo en este momento. Intenta nuevamente; si el problema continúa, contacta al equipo de RRHH."
          : message || "No fue posible enviar la postulación.",
      );
    } finally {
      setSubmitting(false);
    }
  };

  const requestManualReview = async () => {
    if (!applicationId || !cvFile) return;
    setRequestingManualReview(true);
    setError("");
    try {
      const payload = new FormData();
      payload.append("applicationId", applicationId);
      payload.append("authorized", "true");
      payload.append("reason", "PDF sin texto extraíble después de tres intentos");
      payload.append("cv", cvFile, cvFile.name);
      const result = await request("/public/applications/manual-review", {
        method: "POST", body: payload,
      });
      setTicketId(result.ticketId || ticketId);
      setSuccess(`Documento enviado a revisión manual. Ticket: ${result.ticketId || ticketId}`);
      setCanRequestManualReview(false);
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setRequestingManualReview(false);
    }
  };

  return (
    <PublicLayout>
      <div className="panel application-panel">
        <p className="eyebrow">Postulación</p>
        <h1>Completa tus datos</h1>
        <div className="application-progress" aria-label="Progreso de la postulación">
          {["Datos", "CV", "Validación", "Confirmación"].map((label, index) => (
            <span className={submitting ? (index <= 2 ? "active" : "") : success ? "active" : index <= 1 ? "active" : ""} key={label}>
              {index + 1}. {label}
            </span>
          ))}
        </div>
        <form onSubmit={submit} className="application-form">
          <div className="form-grid">
            <label className="field">
              <span>Nombre</span>
              <input
                value={form.firstName}
                onChange={(e) => setForm({ ...form, firstName: e.target.value })}
                maxLength={80}
                required
              />
            </label>
            <label className="field">
              <span>Apellidos</span>
              <input value={form.lastName} onChange={(e) => setForm({ ...form, lastName: e.target.value })} maxLength={100} required />
            </label>
            <label className="field">
              <span>Correo electrónico</span>
              <input
                type="email"
                value={form.email}
                onChange={(e) => setForm({ ...form, email: e.target.value })}
                placeholder="nombre@correo.com"
                required
              />
            </label>
            <label className="field">
              <span>Teléfono</span>
              <input
                value={form.phone}
                onChange={(e) => setForm({ ...form, phone: e.target.value })}
                placeholder="300 123 4567"
              />
            </label>
            <label className="field">
              <span>Años de experiencia</span>
              <input type="number" min="0" max="80" step="0.5" value={form.experienceYears}
                onChange={(e) => setForm({ ...form, experienceYears: e.target.value })} required />
            </label>
          </div>

          <label className="field wide">
            <span>Tecnologías o conocimientos principales</span>
            <input value={form.skills} onChange={(e) => setForm({ ...form, skills: e.target.value })}
              placeholder="Java, PostgreSQL, Docker" maxLength={1000} required />
            <small className="muted">Sepáralos por coma.</small>
          </label>

          <label className="field wide">
            <span>Hoja de vida (PDF)</span>
            <input
              id="cv-file"
              type="file"
              accept="application/pdf"
              onChange={(e) => onFileChange(e.target.files?.[0])}
            />
            {cvFile && <small className="muted">Archivo seleccionado: {cvFile.name}</small>}
            {cvError && <small className="validation-error">{cvError}</small>}
          </label>

          <label className="check consent-box">
            <input
              type="checkbox"
              checked={form.consentAccepted}
              onChange={(e) => setForm({ ...form, consentAccepted: e.target.checked })}
            />
            <span>Acepto el tratamiento de datos y el uso de mi hoja de vida para esta postulación.</span>
          </label>

          {error && <div className="alert error">{error}</div>}
          {success && <div className="alert success">{success}</div>}
          {ticketId && <div className="ticket-box"><strong>Ticket:</strong> {ticketId}</div>}

          {canRequestManualReview && (
            <div className="manual-review-box">
              <p>Este fue el intento {attemptNumber}. La revisión manual solo se realizará si la autorizas.</p>
              <button type="button" className="secondary" onClick={() => document.getElementById("cv-file")?.click()}>
                Cargar otra versión
              </button>
              <button type="button" className="primary" onClick={requestManualReview} disabled={requestingManualReview}>
                {requestingManualReview ? "Enviando..." : "Enviar a revisión manual"}
              </button>
            </div>
          )}

          <div className="wizard-actions">
            <button type="button" className="secondary" onClick={() => navigate(`/vacantes/${vacancyId}`)}>
              Volver
            </button>
            <button type="submit" className="primary" disabled={submitting || !form.consentAccepted}>
              {submitting ? "Validando documento..." : attemptNumber ? "Validar otra versión" : "Enviar postulación"}
            </button>
          </div>
        </form>
      </div>
    </PublicLayout>
  );
}

function CandidatesList() {
  const [candidates, setCandidates] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");

  useEffect(() => {
    setLoading(true);
    request("/admin/candidates")
      .then((result) => setCandidates(Array.isArray(result) ? result : []))
      .catch((e) => setError(e.message))
      .finally(() => setLoading(false));
  }, []);

  return (
    <>
      <PageTitle
        title="Candidatos"
        subtitle="Listado de postulaciones procesadas y evaluadas"
      />
      {error && <div className="alert error">{error}</div>}
      <section className="panel table-panel">
        {loading ? (
          <p className="loading">Cargando candidatos...</p>
        ) : (
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>Ticket</th>
                  <th>Nombre</th>
                  <th>Vacante</th>
                  <th>Score</th>
                  <th>Prioridad</th>
                  <th>Estado</th>
                  <th>Postulación</th>
                  <th>Acciones</th>
                </tr>
              </thead>
              <tbody>
                {candidates.map((c) => (
                  <tr key={c.id}>
                    <td>
                      <strong>{c.ticket}</strong>
                    </td>
                    <td>{c.full_name}</td>
                    <td>{c.vacancy_title}</td>
                    <td>
                      <strong>{c.score || "--"}/100</strong>
                    </td>
                    <td>
                      <span className={`tag priority-${String(c.priority || "").toLowerCase()}`}>
                        {c.priority || "BAJA"}
                      </span>
                    </td>
                    <td>
                      <span className={`state ${String(c.status || "").toLowerCase()}`}>
                        {c.status || "PENDIENTE_REVISION"}
                      </span>
                    </td>
                    <td>
                      {c.applied_at
                        ? new Date(c.applied_at).toLocaleDateString("es-CO")
                        : "--"}
                    </td>
                    <td>
                      <button
                        onClick={() => navigate(`/admin/candidatos/${c.id}`)}
                        className="icon-button"
                        title="Ver detalle"
                      >
                        <FileSearch />
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
            {!candidates.length && (
              <div className="empty-state">
                <Users />
                <h2>No hay candidatos</h2>
                <p>Las postulaciones aparecerán aquí después de ser procesadas.</p>
              </div>
            )}
          </div>
        )}
      </section>
    </>
  );
}

function CandidateDetail({ id }: { id: string }) {
  const [candidate, setCandidate] = useState<any>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");

  useEffect(() => {
    setLoading(true);
    request(`/tf-admin-get-candidate/admin/candidates/${id}`)
      .then((result) => setCandidate(result || null))
      .catch((e) => setError(e.message))
      .finally(() => setLoading(false));
  }, [id]);

  if (loading) {
    return (
      <>
        <PageTitle title="Cargando..." subtitle="Obteniendo detalles del candidato" />
        <div className="panel loading-box">Cargando...</div>
      </>
    );
  }

  if (error) {
    return (
      <>
        <PageTitle title="Error" subtitle="No se pudo cargar el candidato" />
        <div className="alert error">{error}</div>
      </>
    );
  }

  if (!candidate) {
    return (
      <>
        <PageTitle title="No encontrado" subtitle="El candidato solicitado no existe" />
        <section className="panel empty-state">
          <FileSearch />
          <h2>Candidato no encontrado</h2>
        </section>
      </>
    );
  }

  const habilidades = candidate.habilidades || [];
  const criterios = candidate.score_breakdown || [];
  const preguntas = candidate.interview_questions || [];

  return (
    <>
      <PageTitle
        title={candidate.full_name}
        subtitle={`${candidate.ticket} · ${candidate.vacancy_title}`}
        action={
          <button className="secondary" onClick={() => navigate("/admin/candidatos")}>
            Volver
          </button>
        }
      />

      <div className="detail-grid">
        <section className="panel">
          <h2>Información del candidato</h2>
          <div className="info-block">
            <div>
              <span className="label">Nombre</span>
              <p>{candidate.full_name}</p>
            </div>
            <div>
              <span className="label">Correo</span>
              <p>{candidate.email}</p>
            </div>
            <div>
              <span className="label">Teléfono</span>
              <p>{candidate.phone || "--"}</p>
            </div>
            <div>
              <span className="label">Ubicación</span>
              <p>{candidate.location || "--"}</p>
            </div>
            <div>
              <span className="label">Postulación</span>
              <p>
                {candidate.applied_at
                  ? new Date(candidate.applied_at).toLocaleDateString("es-CO")
                  : "--"}
              </p>
            </div>
            <div>
              <span className="label">Experiencia</span>
              <p>{candidate.experience_years || 0} años</p>
            </div>
          </div>
        </section>

        <section className="panel">
          <h2>Evaluación</h2>
          <div className="score-display">
            <div className="score-main">
              <span className="score-value">{candidate.score || 0}</span>
              <span className="score-max">/100</span>
            </div>
            <div>
              <p className="label">Prioridad</p>
              <span className={`tag priority-${String(candidate.priority || "").toLowerCase()}`}>
                {candidate.priority || "BAJA"}
              </span>
            </div>
            <div>
              <p className="label">Estado</p>
              <span className={`state ${String(candidate.status || "").toLowerCase()}`}>
                {candidate.status || "PENDIENTE_REVISION"}
              </span>
            </div>
          </div>
        </section>
      </div>

      {habilidades.length > 0 && (
        <section className="panel">
          <h2>Habilidades detectadas</h2>
          <div className="skills-grid">
            {habilidades.map((skill: any, idx: number) => (
              <div key={idx} className="skill-tag">
                <span>{skill.nombre}</span>
                {skill.evidencia_laboral && <small>Laboral</small>}
              </div>
            ))}
          </div>
        </section>
      )}

      {criterios.length > 0 && (
        <section className="panel">
          <h2>Desglose del score</h2>
          <div className="criteria-table">
            <div className="criteria-header">
              <span>Criterio</span>
              <span>Peso</span>
              <span>Puntos</span>
              <span>Cumple</span>
            </div>
            {criterios.map((crit: any, idx: number) => (
              <div key={idx} className="criteria-row">
                <span>{crit.nombre}</span>
                <span>{crit.peso}</span>
                <span>{crit.puntos}</span>
                <span>{crit.cumple ? "✓" : "✗"}</span>
              </div>
            ))}
          </div>
        </section>
      )}

      {candidate.resumen && (
        <section className="panel">
          <h2>Resumen profesional (IA)</h2>
          <p className="summary-text">{candidate.resumen}</p>
        </section>
      )}

      {preguntas.length > 0 && (
        <section className="panel">
          <h2>Preguntas sugeridas para entrevista</h2>
          <ol className="questions-list">
            {preguntas.map((q: any, idx: number) => (
              <li key={idx}>
                <strong>{q.tema}</strong>
                <p>{q.pregunta}</p>
              </li>
            ))}
          </ol>
        </section>
      )}
    </>
  );
}

function App() {
  const [path, setPath] = useState(location.pathname);
  useEffect(() => {
    const fn = () => setPath(location.pathname);
    addEventListener("popstate", fn);
    return () => removeEventListener("popstate", fn);
  }, []);
  let page: React.ReactNode;

  if (path === "/" || path === "/vacantes") page = <VacancyCatalog />;
  else if (path === "/admin" || path === "/admin/dashboard") page = <Dashboard />;
  else if (path === "/admin/vacantes") page = <VacancyList />;
  else if (path === "/admin/vacantes/nueva") page = <Wizard />;
  else if (path === "/admin/candidatos") page = <CandidatesList />;
  else {
    const match = path.match(/^\/vacantes\/([0-9a-f-]+)$/);
    if (match) page = <VacancyDetail id={match[1]} />;
    else {
      const postMatch = path.match(/^\/postular\/([0-9a-f-]+)$/);
      if (postMatch) page = <ApplicationForm vacancyId={postMatch[1]} />;
      else {
        const adminMatch = path.match(/^\/admin\/vacantes\/([0-9a-f-]+)$/);
        if (adminMatch) page = <Wizard id={adminMatch[1]} />;
        else {
          const candMatch = path.match(/^\/admin\/candidatos\/([0-9a-f-]+)$/);
          if (candMatch) page = <CandidateDetail id={candMatch[1]} />;
          else
            page = (
              <Placeholder
                title={
                  path.includes("revision")
                    ? "Revision documental"
                    : path.includes("metricas")
                      ? "Metricas"
                      : path.includes("configuracion")
                        ? "Configuracion"
                        : "Seccion desconocida"
                }
              />
            );
        }
      }
    }
  }

  if (path === "/") return <VacancyCatalog />;
  if (path === "/vacantes" || path.startsWith("/vacantes/") || path.startsWith("/postular/")) return <>{page}</>;
  return <AdminLayout>{page}</AdminLayout>;
}

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
