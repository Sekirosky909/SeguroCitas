from __future__ import annotations

from datetime import date, time, datetime
from typing import Any, Optional

import pyodbc
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

app = FastAPI(title="API Seguro Médico", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Ajusta SERVER si tu equipo cambia de nombre. En tu caso actual es JOHAM\\SQLEXPRESS.
CONN_STR = (
    "DRIVER={ODBC Driver 18 for SQL Server};"
    "SERVER=JOHAM\\SQLEXPRESS;"
    "DATABASE=SeguroMedicoDB;"
    "Trusted_Connection=yes;"
    "Encrypt=yes;"
    "TrustServerCertificate=yes;"
)

DISPLAY_STATUS = {
    "ReprogramacionSolicitada": "Reprogramación solicitada",
}

DB_STATUS = {
    "Reprogramación solicitada": "ReprogramacionSolicitada",
}


def to_display_status(value: Any) -> str:
    if value is None:
        return ""
    text = str(value)
    return DISPLAY_STATUS.get(text, text)


def to_db_status(value: str) -> str:
    return DB_STATUS.get(value, value)


def get_conn():
    return pyodbc.connect(CONN_STR)


def clean_value(value: Any) -> Any:
    if isinstance(value, (date, time, datetime)):
        return value.isoformat()
    return value


def rows_to_dicts(cursor) -> list[dict[str, Any]]:
    columns = [column[0] for column in cursor.description]
    result: list[dict[str, Any]] = []
    for row in cursor.fetchall():
        item = {columns[index]: clean_value(value) for index, value in enumerate(row)}
        if "estado" in item:
            item["estado"] = to_display_status(item["estado"])
        result.append(item)
    return result


class SolicitudCita(BaseModel):
    identificacion: str
    nombre_completo: str
    telefono: str
    correo: Optional[str] = None
    hospital_id: int
    especialidad_id: int
    motivo: str
    prioridad: str
    fecha_preferida: str
    hora_preferida: str
    solicitado_por: str


class CancelarCita(BaseModel):
    codigo_seguimiento: str
    identificacion: str


class ReprogramarCita(BaseModel):
    codigo_seguimiento: str
    identificacion: str
    fecha_solicitada: str
    hora_solicitada: str
    motivo: Optional[str] = None


class AsignarCita(BaseModel):
    solicitud_id: int
    doctor_id: int
    fecha_cita: str
    hora_cita: str
    asignado_por: str = "admin"
    duracion_minutos: Optional[int] = None


class EstadoCita(BaseModel):
    cita_id: int
    estado_nuevo: str
    observacion: Optional[str] = None
    cambiado_por: str = "admin"


class HospitalNuevo(BaseModel):
    nombre: str
    direccion: str
    telefono: str


class EspecialidadNueva(BaseModel):
    nombre: str
    descripcion: Optional[str] = None


class DoctorNuevo(BaseModel):
    hospital_id: int
    especialidad_id: int
    nombre_completo: str
    consultorio: str
    correo: Optional[str] = None


class DuracionConfig(BaseModel):
    duracion_minutos: int = Field(ge=5, le=240)


class ActiveConfig(BaseModel):
    activo: bool


@app.get("/")
def home():
    return {"mensaje": "API del Seguro Médico funcionando"}


@app.get("/api/catalogos")
def catalogos():
    conn = get_conn()
    try:
        cursor = conn.cursor()
        cursor.execute("SELECT hospital_id, nombre, direccion, telefono, activo FROM Hospital ORDER BY nombre")
        hospitales = rows_to_dicts(cursor)

        cursor.execute("SELECT especialidad_id, nombre, descripcion, activo FROM Especialidad ORDER BY nombre")
        especialidades = rows_to_dicts(cursor)

        cursor.execute(
            """
            SELECT
                d.doctor_id,
                d.nombre_completo,
                d.consultorio,
                d.correo,
                d.activo,
                d.hospital_id,
                h.nombre AS hospital,
                d.especialidad_id,
                e.nombre AS especialidad
            FROM Doctor d
            INNER JOIN Hospital h ON h.hospital_id = d.hospital_id
            INNER JOIN Especialidad e ON e.especialidad_id = d.especialidad_id
            ORDER BY d.nombre_completo
            """
        )
        doctores = rows_to_dicts(cursor)

        cursor.execute("SELECT valor FROM ConfiguracionSistema WHERE nombre = 'DuracionCitaMinutos'")
        row = cursor.fetchone()
        duration = int(row[0]) if row else 30

        return {
            "hospitales": hospitales,
            "especialidades": especialidades,
            "doctores": doctores,
            "duracion_cita_minutos": duration,
        }
    finally:
        conn.close()


@app.post("/api/solicitudes")
def crear_solicitud(data: SolicitudCita):
    conn = get_conn()
    try:
        cursor = conn.cursor()
        cursor.execute(
            """
            EXEC sp_CrearSolicitudPublica
                @identificacion = ?,
                @nombre_completo = ?,
                @telefono = ?,
                @correo = ?,
                @hospital_id = ?,
                @especialidad_id = ?,
                @motivo = ?,
                @prioridad = ?,
                @fecha_preferida = ?,
                @hora_preferida = ?,
                @solicitado_por = ?
            """,
            data.identificacion,
            data.nombre_completo,
            data.telefono,
            data.correo or None,
            data.hospital_id,
            data.especialidad_id,
            data.motivo,
            data.prioridad,
            data.fecha_preferida,
            data.hora_preferida,
            data.solicitado_por,
        )
        row = cursor.fetchone()
        conn.commit()
        return {"solicitud_id": int(row.solicitud_id), "codigo_seguimiento": row.codigo_seguimiento}
    except Exception as exc:
        conn.rollback()
        raise HTTPException(status_code=400, detail=str(exc))
    finally:
        conn.close()


@app.get("/api/solicitudes/recepcion")
def solicitudes_recepcion():
    conn = get_conn()
    try:
        cursor = conn.cursor()
        cursor.execute(
            """
            SELECT
                sc.solicitud_id,
                sc.codigo_seguimiento,
                p.paciente_id,
                p.identificacion,
                p.nombre_completo AS paciente,
                p.telefono,
                p.correo,
                sc.hospital_id,
                h.nombre AS hospital,
                sc.especialidad_id,
                e.nombre AS especialidad,
                sc.motivo,
                sc.prioridad,
                sc.fecha_preferida,
                sc.hora_preferida,
                sc.solicitado_por,
                sc.estado,
                sc.fecha_solicitud,
                c.cita_id,
                c.doctor_id,
                c.fecha_cita,
                c.hora_cita,
                c.duracion_minutos,
                c.estado AS estado_cita,
                sr.reprogramacion_id,
                sr.fecha_solicitada AS nueva_fecha_solicitada,
                sr.hora_solicitada AS nueva_hora_solicitada,
                sr.motivo AS motivo_reprogramacion
            FROM SolicitudCita sc
            INNER JOIN Paciente p ON p.paciente_id = sc.paciente_id
            INNER JOIN Hospital h ON h.hospital_id = sc.hospital_id
            INNER JOIN Especialidad e ON e.especialidad_id = sc.especialidad_id
            LEFT JOIN Cita c ON c.solicitud_id = sc.solicitud_id
            LEFT JOIN SolicitudReprogramacion sr ON sr.solicitud_id = sc.solicitud_id AND sr.estado = 'Pendiente'
            ORDER BY sc.fecha_solicitud DESC
            """
        )
        rows = rows_to_dicts(cursor)
        for item in rows:
            if item.get("estado_cita"):
                item["estado_cita"] = to_display_status(item["estado_cita"])
        return rows
    finally:
        conn.close()


@app.get("/api/citas/lookup")
def consultar_cita(codigo_seguimiento: str, identificacion: str):
    conn = get_conn()
    try:
        cursor = conn.cursor()
        cursor.execute(
            """
            SELECT TOP 1
                sc.solicitud_id,
                sc.codigo_seguimiento,
                p.identificacion,
                p.nombre_completo AS paciente,
                p.telefono,
                p.correo,
                sc.hospital_id,
                h.nombre AS hospital,
                sc.especialidad_id,
                e.nombre AS especialidad,
                sc.motivo,
                sc.prioridad,
                sc.fecha_preferida,
                sc.hora_preferida,
                sc.solicitado_por,
                sc.estado,
                c.cita_id,
                c.doctor_id,
                d.nombre_completo AS doctor,
                d.consultorio,
                c.fecha_cita,
                c.hora_cita,
                c.duracion_minutos,
                c.estado AS estado_cita,
                sr.fecha_solicitada AS nueva_fecha_solicitada,
                sr.hora_solicitada AS nueva_hora_solicitada,
                sr.motivo AS motivo_reprogramacion
            FROM SolicitudCita sc
            INNER JOIN Paciente p ON p.paciente_id = sc.paciente_id
            INNER JOIN Hospital h ON h.hospital_id = sc.hospital_id
            INNER JOIN Especialidad e ON e.especialidad_id = sc.especialidad_id
            LEFT JOIN Cita c ON c.solicitud_id = sc.solicitud_id
            LEFT JOIN Doctor d ON d.doctor_id = c.doctor_id
            LEFT JOIN SolicitudReprogramacion sr ON sr.solicitud_id = sc.solicitud_id AND sr.estado = 'Pendiente'
            WHERE sc.codigo_seguimiento = ? AND p.identificacion = ?
            """,
            codigo_seguimiento,
            identificacion,
        )
        rows = rows_to_dicts(cursor)
        if not rows:
            raise HTTPException(status_code=404, detail="No encontré una cita con ese código y cédula.")
        item = rows[0]
        if item.get("estado_cita"):
            item["estado_cita"] = to_display_status(item["estado_cita"])
        return item
    finally:
        conn.close()


@app.post("/api/citas/cancelar")
def cancelar_cita(data: CancelarCita):
    conn = get_conn()
    try:
        cursor = conn.cursor()
        cursor.execute(
            "EXEC sp_CancelarCitaPublica @codigo_seguimiento = ?, @identificacion = ?",
            data.codigo_seguimiento,
            data.identificacion,
        )
        conn.commit()
        return {"mensaje": "Cita cancelada correctamente"}
    except Exception as exc:
        conn.rollback()
        raise HTTPException(status_code=400, detail=str(exc))
    finally:
        conn.close()


@app.post("/api/citas/reprogramar")
def reprogramar_cita(data: ReprogramarCita):
    conn = get_conn()
    try:
        cursor = conn.cursor()
        cursor.execute(
            """
            EXEC sp_SolicitarReprogramacionPublica
                @codigo_seguimiento = ?,
                @identificacion = ?,
                @fecha_solicitada = ?,
                @hora_solicitada = ?,
                @motivo = ?
            """,
            data.codigo_seguimiento,
            data.identificacion,
            data.fecha_solicitada,
            data.hora_solicitada,
            data.motivo or None,
        )
        conn.commit()
        return {"mensaje": "Reprogramación solicitada correctamente"}
    except Exception as exc:
        conn.rollback()
        raise HTTPException(status_code=400, detail=str(exc))
    finally:
        conn.close()


@app.post("/api/citas/asignar")
def asignar_cita(data: AsignarCita):
    conn = get_conn()
    try:
        cursor = conn.cursor()
        cursor.execute(
            """
            EXEC sp_AsignarDoctorACita
                @solicitud_id = ?,
                @doctor_id = ?,
                @fecha_cita = ?,
                @hora_cita = ?,
                @asignado_por = ?,
                @duracion_minutos = ?
            """,
            data.solicitud_id,
            data.doctor_id,
            data.fecha_cita,
            data.hora_cita,
            data.asignado_por,
            data.duracion_minutos,
        )
        conn.commit()
        return {"mensaje": "Doctor asignado correctamente"}
    except Exception as exc:
        conn.rollback()
        raise HTTPException(status_code=400, detail=str(exc))
    finally:
        conn.close()


@app.get("/api/citas/doctor")
def citas_doctor(doctor_id: Optional[int] = None):
    conn = get_conn()
    try:
        cursor = conn.cursor()
        query = """
            SELECT
                c.cita_id,
                c.solicitud_id,
                c.doctor_id,
                sc.codigo_seguimiento,
                p.nombre_completo AS paciente,
                p.identificacion,
                p.telefono,
                h.nombre AS hospital,
                e.nombre AS especialidad,
                d.nombre_completo AS doctor,
                d.consultorio,
                sc.motivo,
                sc.prioridad,
                c.fecha_cita,
                c.hora_cita,
                c.duracion_minutos,
                c.estado,
                c.observacion
            FROM Cita c
            INNER JOIN SolicitudCita sc ON sc.solicitud_id = c.solicitud_id
            INNER JOIN Paciente p ON p.paciente_id = sc.paciente_id
            INNER JOIN Doctor d ON d.doctor_id = c.doctor_id
            INNER JOIN Hospital h ON h.hospital_id = d.hospital_id
            INNER JOIN Especialidad e ON e.especialidad_id = d.especialidad_id
        """
        params: list[Any] = []
        if doctor_id:
            query += " WHERE c.doctor_id = ?"
            params.append(doctor_id)
        query += " ORDER BY c.fecha_cita, c.hora_cita"
        cursor.execute(query, params)
        return rows_to_dicts(cursor)
    finally:
        conn.close()


@app.post("/api/citas/estado")
def actualizar_estado(data: EstadoCita):
    conn = get_conn()
    try:
        cursor = conn.cursor()
        cursor.execute(
            """
            EXEC sp_ActualizarEstadoCita
                @cita_id = ?,
                @estado_nuevo = ?,
                @observacion = ?,
                @cambiado_por = ?
            """,
            data.cita_id,
            to_db_status(data.estado_nuevo),
            data.observacion or None,
            data.cambiado_por,
        )
        conn.commit()
        return {"mensaje": "Estado actualizado correctamente"}
    except Exception as exc:
        conn.rollback()
        raise HTTPException(status_code=400, detail=str(exc))
    finally:
        conn.close()


@app.post("/api/admin/hospitales")
def crear_hospital(data: HospitalNuevo):
    conn = get_conn()
    try:
        cursor = conn.cursor()
        cursor.execute("""
            EXEC sp_CrearHospital
                @nombre = ?,
                @direccion = ?,
                @telefono = ?
        """, data.nombre, data.direccion, data.telefono)

        conn.commit()
        return {"mensaje": "Hospital agregado correctamente"}

    except Exception as e:
        conn.rollback()
        raise HTTPException(status_code=400, detail=str(e))

    finally:
        conn.close()


@app.post("/api/admin/especialidades")
def crear_especialidad(data: EspecialidadNueva):
    conn = get_conn()
    try:
        cursor = conn.cursor()
        cursor.execute("""
            EXEC sp_CrearEspecialidad
                @nombre = ?,
                @descripcion = ?
        """, data.nombre, data.descripcion)

        conn.commit()
        return {"mensaje": "Especialidad agregada correctamente"}

    except Exception as e:
        conn.rollback()
        raise HTTPException(status_code=400, detail=str(e))

    finally:
        conn.close()

@app.post("/api/admin/doctores")
def crear_doctor(data: DoctorNuevo):
    conn = get_conn()
    try:
        cursor = conn.cursor()

        cursor.execute("""
            EXEC sp_CrearDoctor
                @hospital_id = ?,
                @especialidad_id = ?,
                @nombre_completo = ?,
                @consultorio = ?,
                @correo = ?
        """,
        data.hospital_id,
        data.especialidad_id,
        data.nombre_completo,
        data.consultorio,
        data.correo)

        conn.commit()

        return {"mensaje": "Doctor agregado correctamente"}

    except Exception as e:
        conn.rollback()
        raise HTTPException(status_code=400, detail=str(e))

    finally:
        conn.close()

@app.post("/api/admin/duracion")
def actualizar_duracion(data: DuracionConfig):
    conn = get_conn()
    try:
        cursor = conn.cursor()
        cursor.execute("EXEC sp_ActualizarDuracionCita @duracion_minutos = ?", data.duracion_minutos)
        conn.commit()
        return {"mensaje": "Duración actualizada correctamente"}
    except Exception as exc:
        conn.rollback()
        raise HTTPException(status_code=400, detail=str(exc))
    finally:
        conn.close()


@app.patch("/api/admin/hospitales/{hospital_id}/activo")
def actualizar_hospital_activo(hospital_id: int, data: ActiveConfig):
    return update_active("Hospital", "hospital_id", hospital_id, data.activo)


@app.patch("/api/admin/especialidades/{especialidad_id}/activo")
def actualizar_especialidad_activo(especialidad_id: int, data: ActiveConfig):
    return update_active("Especialidad", "especialidad_id", especialidad_id, data.activo)


@app.patch("/api/admin/doctores/{doctor_id}/activo")
def actualizar_doctor_activo(doctor_id: int, data: ActiveConfig):
    return update_active("Doctor", "doctor_id", doctor_id, data.activo)


def update_active(table: str, key: str, value: int, active: bool):
    allowed = {
        ("Hospital", "hospital_id"),
        ("Especialidad", "especialidad_id"),
        ("Doctor", "doctor_id"),
    }
    if (table, key) not in allowed:
        raise HTTPException(status_code=400, detail="Tabla no permitida")

    conn = get_conn()
    try:
        cursor = conn.cursor()
        cursor.execute(f"UPDATE {table} SET activo = ? WHERE {key} = ?", 1 if active else 0, value)
        if cursor.rowcount == 0:
            raise HTTPException(status_code=404, detail="Registro no encontrado")
        conn.commit()
        return {"mensaje": "Estado actualizado"}
    except HTTPException:
        conn.rollback()
        raise
    except Exception as exc:
        conn.rollback()
        raise HTTPException(status_code=400, detail=str(exc))
    finally:
        conn.close()


@app.get("/api/dashboard")
def dashboard():
    conn = get_conn()
    try:
        cursor = conn.cursor()
        cursor.execute("SELECT COUNT(*) FROM SolicitudCita")
        total = int(cursor.fetchone()[0])
        cursor.execute("SELECT COUNT(*) FROM SolicitudCita WHERE estado = 'Pendiente'")
        pending = int(cursor.fetchone()[0])
        cursor.execute("SELECT COUNT(*) FROM SolicitudCita WHERE estado IN ('Asignada', 'ReprogramacionSolicitada')")
        assigned = int(cursor.fetchone()[0])
        cursor.execute("SELECT COUNT(*) FROM Cita WHERE estado = 'Atendida'")
        done = int(cursor.fetchone()[0])

        cursor.execute("SELECT e.nombre AS label, COUNT(*) AS value FROM SolicitudCita sc INNER JOIN Especialidad e ON e.especialidad_id = sc.especialidad_id GROUP BY e.nombre ORDER BY value DESC")
        specialty = rows_to_dicts(cursor)
        cursor.execute("SELECT h.nombre AS label, COUNT(*) AS value FROM SolicitudCita sc INNER JOIN Hospital h ON h.hospital_id = sc.hospital_id GROUP BY h.nombre ORDER BY value DESC")
        hospital = rows_to_dicts(cursor)
        cursor.execute("SELECT d.nombre_completo AS label, COUNT(*) AS value FROM Cita c INNER JOIN Doctor d ON d.doctor_id = c.doctor_id GROUP BY d.nombre_completo ORDER BY value DESC")
        doctor = rows_to_dicts(cursor)
        cursor.execute("SELECT estado AS label, COUNT(*) AS value FROM SolicitudCita GROUP BY estado ORDER BY value DESC")
        status = rows_to_dicts(cursor)
        for item in status:
            item["label"] = to_display_status(item["label"])

        return {
            "total": total,
            "pending": pending,
            "assigned": assigned,
            "done": done,
            "charts": {
                "specialty": specialty,
                "hospital": hospital,
                "doctor": doctor,
                "status": status,
            },
        }
    finally:
        conn.close()
