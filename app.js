const API_URL = "http://127.0.0.1:8000/api";
const SESSION_KEY = "seguro_medico_admin_session";
const ADMIN_USER = "admin";
const ADMIN_PASSWORD = "Seguro123";
const FINAL_STATUSES = ["Atendida", "Cancelada"];

const $ = (selector) => document.querySelector(selector);
const $$ = (selector) => Array.from(document.querySelectorAll(selector));

let state = {
  settings: { appointmentDurationMinutes: 30 },
  hospitals: [],
  specialties: [],
  doctors: [],
  appointments: [],
  doctorAppointments: [],
  dashboard: null
};

let isAdmin = sessionStorage.getItem(SESSION_KEY) === "true";
let lastPublicAppointment = null;

async function init() {
  bindNavigation();
  bindLogin();
  bindPublicForms();
  bindAdminForms();
  bindFilters();
  setMinimumDates();
  applyAdminMode(isAdmin);
  await refreshAll();
}

async function apiGet(endpoint) {
  const response = await fetch(`${API_URL}${endpoint}`);
  const data = await safeJson(response);
  if (!response.ok) throw new Error(data.detail || "Error consultando la API.");
  return data;
}

async function apiPost(endpoint, payload) {
  const response = await fetch(`${API_URL}${endpoint}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload)
  });
  const data = await safeJson(response);
  if (!response.ok) throw new Error(data.detail || "Error enviando datos a la API.");
  return data;
}

async function apiPatch(endpoint, payload) {
  const response = await fetch(`${API_URL}${endpoint}`, {
    method: "PATCH",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload)
  });
  const data = await safeJson(response);
  if (!response.ok) throw new Error(data.detail || "Error actualizando datos.");
  return data;
}

async function safeJson(response) {
  try { return await response.json(); } catch { return {}; }
}

async function refreshAll() {
  try {
    const [catalogos, solicitudes, dashboard] = await Promise.all([
      apiGet("/catalogos"),
      apiGet("/solicitudes/recepcion"),
      apiGet("/dashboard")
    ]);

    state.hospitals = mapHospitals(catalogos.hospitales || []);
    state.specialties = mapSpecialties(catalogos.especialidades || []);
    state.doctors = mapDoctors(catalogos.doctores || []);
    state.settings.appointmentDurationMinutes = Number(catalogos.duracion_cita_minutos || 30);
    state.appointments = mapAppointments(solicitudes || []);
    state.dashboard = dashboard;

    await refreshDoctorAppointments();
    renderAll();
  } catch (error) {
    showToast(error.message || "No pude conectar con la API.");
    renderOfflineMessage();
  }
}

async function refreshDoctorAppointments() {
  try {
    const doctorId = Number($("#doctor-selector")?.value || 0);
    const endpoint = doctorId ? `/citas/doctor?doctor_id=${doctorId}` : "/citas/doctor";
    const data = await apiGet(endpoint);
    state.doctorAppointments = mapDoctorAppointments(data || []);
  } catch {
    state.doctorAppointments = [];
  }
}

function renderOfflineMessage() {
  ["reception-list", "doctor-list"].forEach(id => {
    const el = document.getElementById(id);
    if (el) el.innerHTML = `<div class="warning-box">No hay conexión con FastAPI. Ejecuta <code>uvicorn api:app --reload</code>.</div>`;
  });
}

function mapHospitals(items) {
  return items.map(item => ({
    id: Number(item.hospital_id),
    name: item.nombre,
    address: item.direccion,
    phone: item.telefono,
    active: Boolean(item.activo)
  }));
}

function mapSpecialties(items) {
  return items.map(item => ({
    id: Number(item.especialidad_id),
    name: item.nombre,
    description: item.descripcion || "Sin descripción",
    active: Boolean(item.activo)
  }));
}

function mapDoctors(items) {
  return items.map(item => ({
    id: Number(item.doctor_id),
    name: item.nombre_completo,
    specialtyId: Number(item.especialidad_id),
    hospitalId: Number(item.hospital_id),
    room: item.consultorio,
    email: item.correo || "",
    active: Boolean(item.activo)
  }));
}

function mapAppointments(items) {
  return items.map(item => ({
    id: Number(item.solicitud_id),
    citaId: item.cita_id ? Number(item.cita_id) : null,
    trackingCode: item.codigo_seguimiento,
    patientName: item.paciente,
    patientId: item.identificacion,
    phone: item.telefono,
    email: item.correo || "",
    hospitalId: Number(item.hospital_id),
    specialtyId: Number(item.especialidad_id),
    priority: item.prioridad,
    preferredDate: item.fecha_preferida,
    preferredTime: sliceTime(item.hora_preferida),
    appointmentDate: item.fecha_cita || item.fecha_preferida,
    appointmentTime: sliceTime(item.hora_cita || item.hora_preferida),
    durationMinutes: Number(item.duracion_minutos || state.settings.appointmentDurationMinutes),
    reason: item.motivo,
    requestedBy: item.solicitado_por,
    status: item.estado,
    doctorId: item.doctor_id ? Number(item.doctor_id) : null,
    createdAt: item.fecha_solicitud,
    rescheduleRequest: item.nueva_fecha_solicitada ? {
      date: item.nueva_fecha_solicitada,
      time: sliceTime(item.nueva_hora_solicitada),
      note: item.motivo_reprogramacion || "Sin nota adicional"
    } : null
  }));
}

function mapDoctorAppointments(items) {
  return items.map(item => ({
    id: Number(item.cita_id),
    solicitudId: Number(item.solicitud_id),
    trackingCode: item.codigo_seguimiento,
    patientName: item.paciente,
    patientId: item.identificacion,
    phone: item.telefono,
    hospital: item.hospital,
    specialty: item.especialidad,
    doctorId: Number(item.doctor_id),
    doctor: item.doctor,
    room: item.consultorio,
    priority: item.prioridad,
    reason: item.motivo,
    appointmentDate: item.fecha_cita,
    appointmentTime: sliceTime(item.hora_cita),
    durationMinutes: Number(item.duracion_minutos),
    status: item.estado,
    observation: item.observacion || ""
  }));
}

function sliceTime(value) {
  if (!value) return "";
  return String(value).slice(0, 5);
}

function bindNavigation() {
  $$(".nav-btn").forEach(button => {
    button.addEventListener("click", () => showScreen(button.dataset.screen));
  });
}

function showScreen(screenId) {
  const target = document.getElementById(screenId);
  if (!target) return;

  if (target.classList.contains("admin-screen") && !isAdmin) {
    openLogin();
    showToast("Debes iniciar sesión como administrador.");
    return;
  }

  $$(".nav-btn").forEach(btn => btn.classList.toggle("active", btn.dataset.screen === screenId));
  $$(".screen").forEach(screen => screen.classList.remove("active-screen"));
  target.classList.add("active-screen");

  if (screenId === "doctor-screen") refreshDoctorAppointments().then(renderDoctorPanel);
  else renderAll();
}

function bindLogin() {
  $("#admin-login-button").addEventListener("click", openLogin);
  $("#admin-logout-button").addEventListener("click", () => {
    isAdmin = false;
    sessionStorage.removeItem(SESSION_KEY);
    applyAdminMode(false);
    showScreen("public-screen");
    showToast("Sesión administrativa cerrada.");
  });
  $("#close-login").addEventListener("click", closeLogin);
  $("#login-modal").addEventListener("click", event => {
    if (event.target.id === "login-modal") closeLogin();
  });
  $("#login-form").addEventListener("submit", event => {
    event.preventDefault();
    const user = $("#admin-user").value.trim();
    const password = $("#admin-password").value;

    if (user === ADMIN_USER && password === ADMIN_PASSWORD) {
      isAdmin = true;
      sessionStorage.setItem(SESSION_KEY, "true");
      $("#login-form").reset();
      closeLogin();
      applyAdminMode(true);
      showScreen("admin-screen");
      showToast("Bienvenido al panel administrativo.");
    } else {
      showToast("Usuario o contraseña incorrectos.");
    }
  });
}

function openLogin() {
  $("#login-modal").classList.remove("hidden");
  $("#login-modal").setAttribute("aria-hidden", "false");
  setTimeout(() => $("#admin-user").focus(), 50);
}

function closeLogin() {
  $("#login-modal").classList.add("hidden");
  $("#login-modal").setAttribute("aria-hidden", "true");
}

function applyAdminMode(active) {
  $$(".admin-only").forEach(element => element.classList.toggle("hidden", !active));
  $("#admin-login-button").classList.toggle("hidden", active);
  $("#admin-logout-button").classList.toggle("hidden", !active);
}

function bindPublicForms() {
  $("#appointment-form").addEventListener("submit", async event => {
    event.preventDefault();
    const payload = {
      identificacion: $("#patient-id").value.trim(),
      nombre_completo: $("#patient-name").value.trim(),
      telefono: $("#patient-phone").value.trim(),
      correo: $("#patient-email").value.trim() || null,
      hospital_id: Number($("#hospital").value),
      especialidad_id: Number($("#specialty").value),
      motivo: $("#reason").value.trim(),
      prioridad: $("#priority").value,
      fecha_preferida: $("#preferred-date").value,
      hora_preferida: $("#preferred-time").value,
      solicitado_por: $("#requested-by").value.trim()
    };

    try {
      const response = await apiPost("/solicitudes", payload);
      $("#appointment-form").reset();
      setMinimumDates();
      $("#tracking-result").classList.remove("hidden");
      $("#tracking-result").innerHTML = `
        <strong>Solicitud enviada a SQL Server.</strong><br>
        Guarda este código para consultar, cancelar o pedir cambio de cita:<br>
        <code>${escapeHTML(response.codigo_seguimiento)}</code>
      `;
      await refreshAll();
      showToast("Solicitud enviada correctamente.");
    } catch (error) {
      showToast(error.message);
    }
  });

  $("#lookup-form").addEventListener("submit", async event => {
    event.preventDefault();
    const code = encodeURIComponent($("#lookup-code").value.trim().toUpperCase());
    const patientId = encodeURIComponent($("#lookup-patient-id").value.trim());

    try {
      const data = await apiGet(`/citas/lookup?codigo_seguimiento=${code}&identificacion=${patientId}`);
      lastPublicAppointment = mapPublicLookup(data);
      renderPublicAppointmentResult();
    } catch (error) {
      lastPublicAppointment = null;
      $("#public-appointment-result").innerHTML = `<div class="warning-box">${escapeHTML(error.message)}</div>`;
    }
  });
}

function mapPublicLookup(item) {
  return {
    id: Number(item.solicitud_id),
    citaId: item.cita_id ? Number(item.cita_id) : null,
    trackingCode: item.codigo_seguimiento,
    patientName: item.paciente,
    patientId: item.identificacion,
    hospital: item.hospital,
    hospitalId: Number(item.hospital_id),
    specialty: item.especialidad,
    specialtyId: Number(item.especialidad_id),
    priority: item.prioridad,
    reason: item.motivo,
    status: item.estado,
    doctor: item.doctor || "Pendiente de asignación",
    appointmentDate: item.fecha_cita || item.fecha_preferida,
    appointmentTime: sliceTime(item.hora_cita || item.hora_preferida),
    durationMinutes: Number(item.duracion_minutos || state.settings.appointmentDurationMinutes),
    rescheduleRequest: item.nueva_fecha_solicitada ? {
      date: item.nueva_fecha_solicitada,
      time: sliceTime(item.nueva_hora_solicitada),
      note: item.motivo_reprogramacion || "Sin nota adicional"
    } : null
  };
}

function bindAdminForms() {
  $("#settings-form").addEventListener("submit", async event => {
    event.preventDefault();
    const duration = Number($("#duration-minutes").value);
    try {
      await apiPost("/admin/duracion", { duracion_minutos: duration });
      await refreshAll();
      showToast(`Tiempo X guardado en SQL: ${duration} minutos.`);
    } catch (error) {
      showToast(error.message);
    }
  });

  $("#hospital-form").addEventListener("submit", async event => {
    event.preventDefault();
    try {
      await apiPost("/admin/hospitales", {
        nombre: $("#hospital-name").value.trim(),
        direccion: $("#hospital-address").value.trim(),
        telefono: $("#hospital-phone").value.trim()
      });
      $("#hospital-form").reset();
      await refreshAll();
      showToast("Hospital agregado en SQL Server.");
    } catch (error) { showToast(error.message); }
  });

  $("#specialty-form").addEventListener("submit", async event => {
    event.preventDefault();
    try {
      await apiPost("/admin/especialidades", {
        nombre: $("#specialty-name").value.trim(),
        descripcion: $("#specialty-description").value.trim() || null
      });
      $("#specialty-form").reset();
      await refreshAll();
      showToast("Especialidad agregada en SQL Server.");
    } catch (error) { showToast(error.message); }
  });

  $("#doctor-form").addEventListener("submit", async event => {
    event.preventDefault();
    try {
      await apiPost("/admin/doctores", {
        nombre_completo: $("#doctor-name").value.trim(),
        hospital_id: Number($("#doctor-hospital").value),
        especialidad_id: Number($("#doctor-specialty").value),
        consultorio: $("#doctor-room").value.trim(),
        correo: $("#doctor-email").value.trim() || null
      });
      $("#doctor-form").reset();
      await refreshAll();
      showToast("Doctor agregado en SQL Server.");
    } catch (error) { showToast(error.message); }
  });

  $("#reset-demo").addEventListener("click", () => {
    alert("Para reiniciar la demo real, vuelve a ejecutar database.sql en SSMS. Esto protege tu BD contra borrados accidentales desde la web.");
  });
}

function bindFilters() {
  $("#status-filter").addEventListener("change", renderReceptionPanel);
  $("#search-patient").addEventListener("input", renderReceptionPanel);
  $("#doctor-selector").addEventListener("change", async () => {
    await refreshDoctorAppointments();
    renderDoctorPanel();
  });
}

function renderAll() {
  renderSelects();
  renderAdminPanel();
  renderReceptionPanel();
  renderDoctorPanel();
  renderDashboard();
}

function renderSelects() {
  const activeHospitals = state.hospitals.filter(item => item.active);
  const activeSpecialties = state.specialties.filter(item => item.active);
  const activeDoctors = state.doctors.filter(item => item.active);

  fillSelect("#hospital", activeHospitals, "Seleccione hospital");
  fillSelect("#specialty", activeSpecialties, "Seleccione especialidad");
  fillSelect("#doctor-hospital", activeHospitals, "Seleccione hospital");
  fillSelect("#doctor-specialty", activeSpecialties, "Seleccione especialidad");

  const currentDoctor = $("#doctor-selector").value;
  $("#doctor-selector").innerHTML = activeDoctors.length
    ? activeDoctors.map(doctor => `<option value="${doctor.id}">${escapeHTML(doctor.name)} · ${escapeHTML(getSpecialtyName(doctor.specialtyId))}</option>`).join("")
    : `<option value="">No hay doctores activos</option>`;
  if (currentDoctor && activeDoctors.some(doctor => String(doctor.id) === currentDoctor)) $("#doctor-selector").value = currentDoctor;

  $("#duration-minutes").value = state.settings.appointmentDurationMinutes;
  $("#hero-duration-label").textContent = `Duración: ${state.settings.appointmentDurationMinutes} min`;
}

function fillSelect(selector, items, placeholder) {
  const select = $(selector);
  const current = select.value;
  select.innerHTML = `<option value="">${placeholder}</option>` + items.map(item => `<option value="${item.id}">${escapeHTML(item.name)}</option>`).join("");
  if (current && items.some(item => String(item.id) === current)) select.value = current;
}

function renderAdminPanel() {
  renderMiniList("#hospital-list", state.hospitals, item => `${escapeHTML(item.address)} · ${escapeHTML(item.phone)}`, toggleHospital);
  renderMiniList("#specialty-list", state.specialties, item => escapeHTML(item.description || "Sin descripción"), toggleSpecialty);

  const container = $("#doctor-admin-list");
  container.innerHTML = state.doctors.length
    ? state.doctors.map(doctor => `
      <div class="mini-item">
        <div>
          <strong>${escapeHTML(doctor.name)} ${doctor.active ? "" : "(inactivo)"}</strong>
          <span>${escapeHTML(getSpecialtyName(doctor.specialtyId))} · ${escapeHTML(getHospitalName(doctor.hospitalId))} · ${escapeHTML(doctor.room)}</span>
        </div>
        <button class="small-btn" data-toggle-doctor="${doctor.id}">${doctor.active ? "Desactivar" : "Activar"}</button>
      </div>
    `).join("")
    : `<div class="empty-state">No hay doctores registrados.</div>`;

  container.querySelectorAll("[data-toggle-doctor]").forEach(button => {
    button.addEventListener("click", () => toggleDoctor(Number(button.dataset.toggleDoctor)));
  });
}

function renderMiniList(selector, items, subtitleBuilder, toggleHandler) {
  const container = $(selector);
  container.innerHTML = items.length
    ? items.map(item => `
      <div class="mini-item">
        <div>
          <strong>${escapeHTML(item.name)} ${item.active ? "" : "(inactivo)"}</strong>
          <span>${subtitleBuilder(item)}</span>
        </div>
        <button class="small-btn" data-toggle="${item.id}">${item.active ? "Desactivar" : "Activar"}</button>
      </div>
    `).join("")
    : `<div class="empty-state">No hay registros.</div>`;

  container.querySelectorAll("[data-toggle]").forEach(button => {
    button.addEventListener("click", () => toggleHandler(Number(button.dataset.toggle)));
  });
}

function renderReceptionPanel() {
  const selectedStatus = $("#status-filter").value;
  const search = $("#search-patient").value.toLowerCase().trim();

  const filtered = state.appointments.filter(appointment => {
    const matchesStatus = selectedStatus === "Todos" || appointment.status === selectedStatus;
    const matchesSearch = !search ||
      appointment.patientName.toLowerCase().includes(search) ||
      appointment.patientId.toLowerCase().includes(search) ||
      appointment.trackingCode.toLowerCase().includes(search);
    return matchesStatus && matchesSearch;
  });

  $("#reception-list").innerHTML = filtered.length
    ? filtered.map(renderReceptionCard).join("")
    : `<div class="empty-state">No hay citas con esos filtros.</div>`;

  $$('[data-assign]').forEach(button => button.addEventListener("click", () => assignDoctor(Number(button.dataset.assign))));
  $$('[data-cancel-admin]').forEach(button => button.addEventListener("click", () => cancelAdmin(Number(button.dataset.cancelAdmin))));
  $$('[data-delete]').forEach(button => button.addEventListener("click", () => showToast("El borrado físico se deshabilitó porque ahora los datos viven en SQL Server.")));
}

function renderReceptionCard(appointment) {
  const compatibleDoctors = getCompatibleDoctors(appointment);
  const selectedDoctor = getDoctor(appointment.doctorId);
  const requestedDate = appointment.rescheduleRequest?.date || appointment.appointmentDate || appointment.preferredDate;
  const requestedTime = appointment.rescheduleRequest?.time || appointment.appointmentTime || appointment.preferredTime;
  const canAssign = compatibleDoctors.length > 0 && !FINAL_STATUSES.includes(appointment.status);

  return `
    <article class="appointment-card priority-${escapeHTML(appointment.priority)}">
      <div>
        ${statusBadge(appointment.status)}
        <h3>${escapeHTML(appointment.patientName)}</h3>
        <p>${escapeHTML(appointment.reason)}</p>
        <div class="meta-grid">
          <div class="meta"><span>Código</span>${escapeHTML(appointment.trackingCode)}</div>
          <div class="meta"><span>Cédula</span>${escapeHTML(appointment.patientId)}</div>
          <div class="meta"><span>Teléfono</span>${escapeHTML(appointment.phone)}</div>
          <div class="meta"><span>Hospital</span>${escapeHTML(getHospitalName(appointment.hospitalId))}</div>
          <div class="meta"><span>Especialidad</span>${escapeHTML(getSpecialtyName(appointment.specialtyId))}</div>
          <div class="meta"><span>Prioridad</span>${escapeHTML(appointment.priority)}</div>
          <div class="meta"><span>Fecha solicitada</span>${formatDate(appointment.preferredDate)} · ${escapeHTML(appointment.preferredTime)}</div>
          <div class="meta"><span>Solicitado por</span>${escapeHTML(appointment.requestedBy)}</div>
        </div>
        ${selectedDoctor ? `<div class="notice"><strong>Doctor asignado:</strong> ${escapeHTML(selectedDoctor.name)} · ${escapeHTML(getHospitalName(selectedDoctor.hospitalId))} · ${escapeHTML(selectedDoctor.room)}<br><strong>Horario:</strong> ${formatDate(appointment.appointmentDate)} · ${escapeHTML(appointment.appointmentTime)} · ${appointment.durationMinutes} min</div>` : ""}
        ${appointment.rescheduleRequest ? `<div class="warning-box"><strong>Solicitud de reprogramación:</strong> ${formatDate(appointment.rescheduleRequest.date)} · ${escapeHTML(appointment.rescheduleRequest.time)}<br>${escapeHTML(appointment.rescheduleRequest.note || "Sin nota adicional")}</div>` : ""}
      </div>
      <div class="card-actions">
        <label>Doctor compatible
          <select id="doctor-${appointment.id}" ${canAssign ? "" : "disabled"}>
            ${compatibleDoctors.length ? compatibleDoctors.map(doctor => `<option value="${doctor.id}" ${doctor.id === appointment.doctorId ? "selected" : ""}>${escapeHTML(doctor.name)} · ${escapeHTML(doctor.room)}</option>`).join("") : `<option>No hay doctor compatible</option>`}
          </select>
        </label>
        <label>Fecha aprobada<input type="date" id="date-${appointment.id}" value="${escapeHTML(requestedDate)}" ${canAssign ? "" : "disabled"} /></label>
        <label>Hora aprobada<input type="time" id="time-${appointment.id}" value="${escapeHTML(requestedTime)}" ${canAssign ? "" : "disabled"} /></label>
        <button class="primary-btn" data-assign="${appointment.id}" ${canAssign ? "" : "disabled"}>Asignar / aprobar cita</button>
        <button class="secondary-btn" data-cancel-admin="${appointment.id}" ${FINAL_STATUSES.includes(appointment.status) ? "disabled" : ""}>Cancelar cita</button>
        <button class="danger-btn" data-delete="${appointment.id}">Eliminar registro</button>
      </div>
    </article>
  `;
}

function renderDoctorPanel() {
  $("#doctor-list").innerHTML = state.doctorAppointments.length
    ? state.doctorAppointments.map(renderDoctorCard).join("")
    : `<div class="empty-state">Este doctor todavía no tiene citas asignadas.</div>`;

  $$('[data-status-id]').forEach(select => {
    select.addEventListener("change", () => updateAppointmentStatus(Number(select.dataset.statusId), select.value, "Actualizado por doctor."));
  });
}

function renderDoctorCard(appointment) {
  return `
    <article class="appointment-card priority-${escapeHTML(appointment.priority)}">
      <div>
        ${statusBadge(appointment.status)}
        <h3>${escapeHTML(appointment.patientName)}</h3>
        <p>${escapeHTML(appointment.reason)}</p>
        <div class="meta-grid">
          <div class="meta"><span>Código</span>${escapeHTML(appointment.trackingCode)}</div>
          <div class="meta"><span>Identificación</span>${escapeHTML(appointment.patientId)}</div>
          <div class="meta"><span>Teléfono</span>${escapeHTML(appointment.phone)}</div>
          <div class="meta"><span>Hospital</span>${escapeHTML(appointment.hospital)}</div>
          <div class="meta"><span>Especialidad</span>${escapeHTML(appointment.specialty)}</div>
          <div class="meta"><span>Fecha y hora</span>${formatDate(appointment.appointmentDate)} · ${escapeHTML(appointment.appointmentTime)}</div>
          <div class="meta"><span>Duración</span>${appointment.durationMinutes} minutos</div>
        </div>
      </div>
      <div class="card-actions">
        <label>Estado de atención
          <select data-status-id="${appointment.id}">
            ${["Asignada", "Confirmada", "Atendida", "Cancelada"].map(status => `<option value="${status}" ${status === appointment.status ? "selected" : ""}>${status}</option>`).join("")}
          </select>
        </label>
      </div>
    </article>
  `;
}

function renderPublicAppointmentResult() {
  const appointment = lastPublicAppointment;
  if (!appointment) {
    $("#public-appointment-result").innerHTML = "";
    return;
  }

  const canModify = !FINAL_STATUSES.includes(appointment.status);
  $("#public-appointment-result").innerHTML = `
    <article class="appointment-card public-card priority-${escapeHTML(appointment.priority)}">
      <div>
        ${statusBadge(appointment.status)}
        <h3>${escapeHTML(appointment.patientName)}</h3>
        <div class="meta-grid">
          <div class="meta"><span>Código</span>${escapeHTML(appointment.trackingCode)}</div>
          <div class="meta"><span>Hospital</span>${escapeHTML(appointment.hospital)}</div>
          <div class="meta"><span>Especialidad</span>${escapeHTML(appointment.specialty)}</div>
          <div class="meta"><span>Fecha</span>${formatDate(appointment.appointmentDate)} · ${escapeHTML(appointment.appointmentTime)}</div>
          <div class="meta"><span>Duración</span>${appointment.durationMinutes} minutos</div>
          <div class="meta"><span>Doctor</span>${escapeHTML(appointment.doctor)}</div>
        </div>
        ${appointment.rescheduleRequest ? `<div class="warning-box">Ya existe una solicitud de cambio para ${formatDate(appointment.rescheduleRequest.date)} · ${escapeHTML(appointment.rescheduleRequest.time)}.</div>` : ""}
      </div>
      <div class="card-actions">
        <button class="danger-btn" id="public-cancel-btn" ${canModify ? "" : "disabled"}>Quitar / cancelar cita</button>
        <form id="reschedule-form">
          <label>Nueva fecha solicitada<input type="date" id="reschedule-date" required ${canModify ? "" : "disabled"} /></label>
          <label>Nueva hora solicitada<input type="time" id="reschedule-time" required ${canModify ? "" : "disabled"} /></label>
          <label>Motivo del cambio<textarea id="reschedule-note" rows="3" placeholder="Explica por qué deseas cambiar la cita" ${canModify ? "" : "disabled"}></textarea></label>
          <button class="secondary-btn" type="submit" ${canModify ? "" : "disabled"}>Solicitar cambio de cita</button>
        </form>
      </div>
    </article>
  `;

  $("#reschedule-date").min = new Date().toISOString().split("T")[0];
  $("#public-cancel-btn").addEventListener("click", cancelPublicAppointment);
  $("#reschedule-form").addEventListener("submit", event => {
    event.preventDefault();
    requestReschedule();
  });
}

function renderDashboard() {
  const dashboard = state.dashboard || { total: 0, pending: 0, assigned: 0, done: 0, charts: {} };
  $("#hero-active-count").textContent = dashboard.total || 0;
  $("#stat-total").textContent = dashboard.total || 0;
  $("#stat-pending").textContent = dashboard.pending || 0;
  $("#stat-assigned").textContent = dashboard.assigned || 0;
  $("#stat-done").textContent = dashboard.done || 0;

  renderBarChart("specialty-chart", dashboard.charts?.specialty || []);
  renderBarChart("hospital-chart", dashboard.charts?.hospital || []);
  renderBarChart("doctor-chart", dashboard.charts?.doctor || []);
  renderBarChart("status-chart", dashboard.charts?.status || []);
}

function renderBarChart(containerId, rows) {
  const container = document.getElementById(containerId);
  const max = Math.max(...rows.map(row => Number(row.value)), 1);
  container.innerHTML = rows.length
    ? rows.map(row => `
      <div class="bar-row">
        <strong title="${escapeHTML(row.label)}">${escapeHTML(row.label)}</strong>
        <div class="bar-track"><div class="bar-fill" style="width: ${(Number(row.value) / max) * 100}%"></div></div>
        <span>${Number(row.value)}</span>
      </div>
    `).join("")
    : `<div class="empty-state">No hay datos suficientes.</div>`;
}

async function assignDoctor(appointmentId) {
  const doctorId = Number($(`#doctor-${appointmentId}`).value);
  const appointmentDate = $(`#date-${appointmentId}`).value;
  const appointmentTime = $(`#time-${appointmentId}`).value;

  if (!doctorId || !appointmentDate || !appointmentTime) {
    showToast("Selecciona doctor, fecha y hora.");
    return;
  }

  try {
    await apiPost("/citas/asignar", {
      solicitud_id: appointmentId,
      doctor_id: doctorId,
      fecha_cita: appointmentDate,
      hora_cita: appointmentTime,
      asignado_por: "admin",
      duracion_minutos: state.settings.appointmentDurationMinutes
    });
    await refreshAll();
    showToast("Cita aprobada y doctor asignado correctamente.");
  } catch (error) {
    showToast(error.message);
  }
}

async function updateAppointmentStatus(citaId, status, note) {
  try {
    await apiPost("/citas/estado", {
      cita_id: citaId,
      estado_nuevo: status,
      observacion: note,
      cambiado_por: "doctor"
    });
    await refreshAll();
    showToast(`Estado actualizado a ${status}.`);
  } catch (error) {
    showToast(error.message);
  }
}

async function cancelAdmin(solicitudId) {
  const appointment = state.appointments.find(item => item.id === solicitudId);
  if (!appointment) return;
  if (!confirm(`¿Cancelar la cita ${appointment.trackingCode}?`)) return;

  try {
    await apiPost("/citas/cancelar", {
      codigo_seguimiento: appointment.trackingCode,
      identificacion: appointment.patientId
    });
    await refreshAll();
    showToast("Cita cancelada por recepción.");
  } catch (error) { showToast(error.message); }
}

async function cancelPublicAppointment() {
  if (!lastPublicAppointment) return;
  if (!confirm(`¿Cancelar la cita ${lastPublicAppointment.trackingCode}?`)) return;

  try {
    await apiPost("/citas/cancelar", {
      codigo_seguimiento: lastPublicAppointment.trackingCode,
      identificacion: lastPublicAppointment.patientId
    });
    lastPublicAppointment.status = "Cancelada";
    renderPublicAppointmentResult();
    await refreshAll();
    showToast("Cita cancelada por el usuario.");
  } catch (error) { showToast(error.message); }
}

async function requestReschedule() {
  if (!lastPublicAppointment) return;
  const date = $("#reschedule-date").value;
  const time = $("#reschedule-time").value;
  const note = $("#reschedule-note").value.trim();

  if (!date || !time) {
    showToast("Selecciona nueva fecha y hora.");
    return;
  }

  try {
    await apiPost("/citas/reprogramar", {
      codigo_seguimiento: lastPublicAppointment.trackingCode,
      identificacion: lastPublicAppointment.patientId,
      fecha_solicitada: date,
      hora_solicitada: time,
      motivo: note || null
    });
    lastPublicAppointment.status = "Reprogramación solicitada";
    lastPublicAppointment.rescheduleRequest = { date, time, note };
    renderPublicAppointmentResult();
    await refreshAll();
    showToast("Solicitud de cambio enviada a recepción.");
  } catch (error) { showToast(error.message); }
}

function getCompatibleDoctors(appointment) {
  return state.doctors.filter(doctor => doctor.active && doctor.specialtyId === appointment.specialtyId && doctor.hospitalId === appointment.hospitalId);
}

function getDoctor(doctorId) {
  return state.doctors.find(doctor => doctor.id === Number(doctorId));
}

function getHospitalName(hospitalId) {
  return state.hospitals.find(item => item.id === Number(hospitalId))?.name || "Sin hospital";
}

function getSpecialtyName(specialtyId) {
  return state.specialties.find(item => item.id === Number(specialtyId))?.name || "Sin especialidad";
}

async function toggleHospital(id) {
  const hospital = state.hospitals.find(item => item.id === id);
  if (!hospital) return;
  try {
    await apiPatch(`/admin/hospitales/${id}/activo`, { activo: !hospital.active });
    await refreshAll();
  } catch (error) { showToast(error.message); }
}

async function toggleSpecialty(id) {
  const specialty = state.specialties.find(item => item.id === id);
  if (!specialty) return;
  try {
    await apiPatch(`/admin/especialidades/${id}/activo`, { activo: !specialty.active });
    await refreshAll();
  } catch (error) { showToast(error.message); }
}

async function toggleDoctor(id) {
  const doctor = state.doctors.find(item => item.id === id);
  if (!doctor) return;
  try {
    await apiPatch(`/admin/doctores/${id}/activo`, { activo: !doctor.active });
    await refreshAll();
  } catch (error) { showToast(error.message); }
}

function statusBadge(status) {
  return `<span class="status-badge ${statusClass(status)}">${escapeHTML(status)}</span>`;
}

function statusClass(status) {
  return "status-" + String(status)
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/\s+/g, "-");
}

function formatDate(date) {
  if (!date) return "Sin fecha";
  return new Intl.DateTimeFormat("es-PA", { day: "2-digit", month: "short", year: "numeric" }).format(new Date(`${date}T00:00:00`));
}

function setMinimumDates() {
  const today = new Date().toISOString().split("T")[0];
  $("#preferred-date").min = today;
}

function escapeHTML(value) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function showToast(message) {
  const toast = $("#toast");
  toast.textContent = message;
  toast.classList.add("show");
  setTimeout(() => toast.classList.remove("show"), 3500);
}

init();
