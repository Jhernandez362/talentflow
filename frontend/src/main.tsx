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
};

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
  const headers = options?.body
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
            href="/admin"
            onClick={(e) => {
              e.preventDefault();
              navigate("/admin/dashboard");
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
        await request(`/admin/vacancies/${id}/duplicate`, {
          method: "POST",
          body: JSON.stringify({ code }),
        });
      } else
        await request(`/admin/vacancies/${id}/status`, {
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
  const minimumValid = Boolean(
    String(form.title).trim() &&
    String(form.code).trim() &&
    form.department &&
    form.workMode &&
    form.seniorityLevel &&
    Number(form.openings) > 0 &&
    !salaryInvalid &&
    !datesInvalid,
  );
  const publishValid = minimumValid && criteria.length > 0 && total === 100;
  useEffect(() => {
    if (id)
      request(`/admin/vacancies/${id}`)
        .then((data) => {
          const v = data.vacancy,
            s = data.scoring || {};
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
      const path =
        publish && form.id
          ? `/admin/vacancies/${form.id}/publish`
          : form.id
            ? `/admin/vacancies/${form.id}`
            : "/admin/vacancies";
      const result = await request(path, {
        method: form.id && !publish ? "PUT" : "POST",
        body: JSON.stringify(form),
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
      <section className="panel wizard-panel">
        {step === 0 && (
          <General
            form={form}
            setForm={setForm}
            salaryInvalid={salaryInvalid}
            datesInvalid={datesInvalid}
          />
        )}{" "}
        {step === 1 && <Profile form={form} setForm={setForm} />}{" "}
        {step === 2 && <Score form={form} setForm={setForm} total={total} />}{" "}
        {step === 3 && <Extras form={form} setForm={setForm} />}{" "}
        {step === 4 && <Preview form={form} total={total} />}{" "}
        {step === 5 && (
          <Publish
            total={total}
            minimumValid={minimumValid}
            criteriaCount={criteria.length}
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

function General({
  form,
  setForm,
  salaryInvalid,
  datesInvalid,
}: {
  form: VacancyForm;
  setForm: (v: VacancyForm) => void;
  salaryInvalid: boolean;
  datesInvalid: boolean;
}) {
  const benefits = form.benefits as any[];
  return (
    <>
      <SectionTitle
        n="01"
        title="Informacion general"
        text="Datos publicos y condiciones de la oportunidad"
      />
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
}: {
  form: VacancyForm;
  setForm: (v: VacancyForm) => void;
}) {
  return (
    <>
      <SectionTitle
        n="02"
        title="Perfil requerido"
        text="Experiencia y educacion esperadas, sin penalizar experiencia superior"
      />
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
}: {
  form: VacancyForm;
  setForm: (v: VacancyForm) => void;
  total: number;
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
                  value={c.type}
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
                  value={c.name}
                  onChange={(e) => update(c.id, "name", e.target.value)}
                />
              </Field>
              <Field label="Peso">
                <input
                  type="number"
                  min="0"
                  max="100"
                  value={c.weight}
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
                  value={c.aliases.join(", ")}
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
                  value={c.description}
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
            value={x.name}
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
            value={x.name}
            onChange={(e) => update(x.id, "name", e.target.value)}
          />
          <input
            placeholder="Descripcion opcional"
            value={x.description}
            onChange={(e) => update(x.id, "description", e.target.value)}
          />
          {withType && (
            <select
              value={x.type}
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
            value={x.relevance}
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
  minimumValid,
  criteriaCount,
}: {
  total: number;
  minimumValid: boolean;
  criteriaCount: number;
}) {
  const checks = [
    [minimumValid, "Datos generales y fechas validos"],
    [criteriaCount > 0, "Al menos un criterio evaluable"],
    [total === 100, "Score asignado exactamente en 100 puntos"],
  ];
  return (
    <>
      <SectionTitle
        n="06"
        title="Publicacion"
        text="La persistencia volvera a validar todas las reglas"
      />
      <div className="publish-checks">
        {checks.map(([ok, text]) => (
          <div className={ok ? "ok" : "pending"} key={String(text)}>
            {ok ? <Check /> : <X />}
            <span>{text}</span>
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
        <div className="public-brand">
          <span>TalentFlow</span>
          <small>Bolsa de talento</small>
        </div>
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
    request("/api/public/vacancies")
      .then((result) => setVacancies(Array.isArray(result) ? result : []))
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
    request(`/api/public/vacancies/${id}`)
      .then((result) => setVacancy((result as PublicVacancy) || null))
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
    fullName: "",
    email: "",
    phone: "",
    location: "",
    consentAccepted: false,
  });
  const [cvName, setCvName] = useState("");
  const [cvError, setCvError] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState("");
  const [success, setSuccess] = useState("");

  const onFileChange = (file?: File) => {
    if (!file) {
      setCvName("");
      setCvError("Debes adjuntar tu hoja de vida en PDF.");
      return;
    }

    const isPdf = file.type === "application/pdf" || file.name.toLowerCase().endsWith(".pdf");
    if (!isPdf) {
      setCvName("");
      setCvError("El archivo debe ser un PDF válido.");
      return;
    }

    if (file.size > 5 * 1024 * 1024) {
      setCvName("");
      setCvError("El PDF no puede superar 5 MB.");
      return;
    }

    setCvName(file.name);
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

    const fileInput = document.getElementById("cv-file") as HTMLInputElement | null;
    const file = fileInput?.files?.[0];
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
      await request("/api/public/applications", {
        method: "POST",
        body: JSON.stringify({
          vacancyId,
          fullName: form.fullName,
          email: form.email,
          phone: form.phone,
          location: form.location,
          consentAccepted: form.consentAccepted,
          cvFileName: file.name,
          cvMimeType: file.type || "application/pdf",
          cvSizeBytes: file.size,
          source: "WEB",
        }),
      });
      setSuccess("Tu postulación fue registrada correctamente.");
      setForm({
        fullName: "",
        email: "",
        phone: "",
        location: "",
        consentAccepted: false,
      });
      if (fileInput) fileInput.value = "";
      setCvName("");
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <PublicLayout>
      <div className="panel application-panel">
        <p className="eyebrow">Postulación</p>
        <h1>Completa tus datos</h1>
        <form onSubmit={submit} className="application-form">
          <div className="form-grid">
            <label className="field">
              <span>Nombre completo</span>
              <input
                value={form.fullName}
                onChange={(e) => setForm({ ...form, fullName: e.target.value })}
                placeholder="Tu nombre completo"
                required
              />
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
              <span>Ubicación</span>
              <input
                value={form.location}
                onChange={(e) => setForm({ ...form, location: e.target.value })}
                placeholder="Ciudad o país"
              />
            </label>
          </div>

          <label className="field wide">
            <span>Hoja de vida (PDF)</span>
            <input
              id="cv-file"
              type="file"
              accept="application/pdf"
              onChange={(e) => onFileChange(e.target.files?.[0])}
            />
            {cvName && <small className="muted">Archivo seleccionado: {cvName}</small>}
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

          <div className="wizard-actions">
            <button type="button" className="secondary" onClick={() => navigate(`/vacantes/${vacancyId}`)}>
              Volver
            </button>
            <button type="submit" className="primary" disabled={submitting || !form.consentAccepted}>
              {submitting ? "Enviando..." : "Enviar postulación"}
            </button>
          </div>
        </form>
      </div>
    </PublicLayout>
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
  else {
    const match = path.match(/^\/vacantes\/([0-9a-f-]+)$/);
    if (match) page = <VacancyDetail id={match[1]} />;
    else {
      const postMatch = path.match(/^\/postular\/([0-9a-f-]+)$/);
      if (postMatch) page = <ApplicationForm vacancyId={postMatch[1]} />;
      else {
        const adminMatch = path.match(/^\/admin\/vacantes\/([0-9a-f-]+)$/);
        if (adminMatch) page = <Wizard id={adminMatch[1]} />;
        else
          page = (
            <Placeholder
              title={
                path.includes("candidatos")
                  ? "Candidatos"
                  : path.includes("revision")
                    ? "Revision documental"
                    : path.includes("metricas")
                      ? "Metricas"
                      : "Configuracion"
              }
            />
          );
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
