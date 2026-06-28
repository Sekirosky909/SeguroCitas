/*
  Proyecto BD-II: Sistema de seguro médico para solicitud, cancelación,
  reprogramación y asignación de citas.

  Gestor sugerido: SQL Server / SSMS.
  Incluye: tablas en 3FN, restricciones, vistas, función, procedimientos,
  triggers, datos de prueba y configuración de duración X por cita.
*/

IF DB_ID('SeguroMedicoDB') IS NOT NULL
BEGIN
    ALTER DATABASE SeguroMedicoDB SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE SeguroMedicoDB;
END;
GO

CREATE DATABASE SeguroMedicoDB;
GO

USE SeguroMedicoDB;
GO

CREATE TABLE Hospital (
    hospital_id INT IDENTITY(1,1) PRIMARY KEY,
    nombre VARCHAR(120) NOT NULL UNIQUE,
    direccion VARCHAR(250) NOT NULL,
    telefono VARCHAR(25) NOT NULL,
    activo BIT NOT NULL DEFAULT 1,
    fecha_registro DATETIME2 NOT NULL DEFAULT SYSDATETIME()
);
GO

CREATE TABLE Especialidad (
    especialidad_id INT IDENTITY(1,1) PRIMARY KEY,
    nombre VARCHAR(80) NOT NULL UNIQUE,
    descripcion VARCHAR(250) NULL,
    activo BIT NOT NULL DEFAULT 1,
    fecha_registro DATETIME2 NOT NULL DEFAULT SYSDATETIME()
);
GO

CREATE TABLE UsuarioSistema (
    usuario_id INT IDENTITY(1,1) PRIMARY KEY,
    usuario VARCHAR(60) NOT NULL UNIQUE,
    clave_hash VARCHAR(256) NOT NULL,
    rol VARCHAR(30) NOT NULL DEFAULT 'Administrador',
    activo BIT NOT NULL DEFAULT 1,
    fecha_registro DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT CK_Usuario_Rol CHECK (rol IN ('Administrador', 'Recepcion', 'Doctor'))
);
GO

CREATE TABLE ConfiguracionSistema (
    configuracion_id INT IDENTITY(1,1) PRIMARY KEY,
    nombre VARCHAR(80) NOT NULL UNIQUE,
    valor VARCHAR(80) NOT NULL,
    descripcion VARCHAR(250) NULL,
    fecha_actualizacion DATETIME2 NOT NULL DEFAULT SYSDATETIME()
);
GO

CREATE TABLE Paciente (
    paciente_id INT IDENTITY(1,1) PRIMARY KEY,
    identificacion VARCHAR(30) NOT NULL UNIQUE,
    nombre_completo VARCHAR(120) NOT NULL,
    telefono VARCHAR(25) NOT NULL,
    correo VARCHAR(120) NULL,
    fecha_registro DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT CK_Paciente_Correo CHECK (correo IS NULL OR correo LIKE '%@%._%')
);
GO

CREATE TABLE Doctor (
    doctor_id INT IDENTITY(1,1) PRIMARY KEY,
    hospital_id INT NOT NULL,
    especialidad_id INT NOT NULL,
    nombre_completo VARCHAR(120) NOT NULL,
    consultorio VARCHAR(40) NOT NULL,
    correo VARCHAR(120) NULL,
    activo BIT NOT NULL DEFAULT 1,
    fecha_registro DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT FK_Doctor_Hospital FOREIGN KEY (hospital_id)
        REFERENCES Hospital(hospital_id),
    CONSTRAINT FK_Doctor_Especialidad FOREIGN KEY (especialidad_id)
        REFERENCES Especialidad(especialidad_id),
    CONSTRAINT CK_Doctor_Correo CHECK (correo IS NULL OR correo LIKE '%@%._%')
);
GO

CREATE TABLE SolicitudCita (
    solicitud_id INT IDENTITY(1,1) PRIMARY KEY,
    codigo_seguimiento VARCHAR(20) NOT NULL UNIQUE,
    paciente_id INT NOT NULL,
    hospital_id INT NOT NULL,
    especialidad_id INT NOT NULL,
    motivo VARCHAR(500) NOT NULL,
    prioridad VARCHAR(15) NOT NULL DEFAULT 'Normal',
    fecha_preferida DATE NOT NULL,
    hora_preferida TIME NOT NULL,
    solicitado_por VARCHAR(120) NOT NULL,
    estado VARCHAR(30) NOT NULL DEFAULT 'Pendiente',
    fecha_solicitud DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT FK_Solicitud_Paciente FOREIGN KEY (paciente_id)
        REFERENCES Paciente(paciente_id),
    CONSTRAINT FK_Solicitud_Hospital FOREIGN KEY (hospital_id)
        REFERENCES Hospital(hospital_id),
    CONSTRAINT FK_Solicitud_Especialidad FOREIGN KEY (especialidad_id)
        REFERENCES Especialidad(especialidad_id),
    CONSTRAINT CK_Solicitud_Prioridad CHECK (prioridad IN ('Normal', 'Alta', 'Urgente')),
    CONSTRAINT CK_Solicitud_Estado CHECK (estado IN ('Pendiente', 'Asignada', 'ReprogramacionSolicitada', 'Cancelada'))
);
GO

CREATE TABLE Cita (
    cita_id INT IDENTITY(1,1) PRIMARY KEY,
    solicitud_id INT NOT NULL UNIQUE,
    doctor_id INT NOT NULL,
    fecha_cita DATE NOT NULL,
    hora_cita TIME NOT NULL,
    duracion_minutos INT NOT NULL,
    estado VARCHAR(20) NOT NULL DEFAULT 'Asignada',
    observacion VARCHAR(500) NULL,
    fecha_asignacion DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
    row_version ROWVERSION,
    CONSTRAINT FK_Cita_Solicitud FOREIGN KEY (solicitud_id)
        REFERENCES SolicitudCita(solicitud_id),
    CONSTRAINT FK_Cita_Doctor FOREIGN KEY (doctor_id)
        REFERENCES Doctor(doctor_id),
    CONSTRAINT CK_Cita_Estado CHECK (estado IN ('Asignada', 'Confirmada', 'Atendida', 'Cancelada')),
    CONSTRAINT CK_Cita_Duracion CHECK (duracion_minutos BETWEEN 5 AND 240),
    CONSTRAINT UQ_Cita_Doctor_FechaHora UNIQUE (doctor_id, fecha_cita, hora_cita)
);
GO

CREATE TABLE SolicitudReprogramacion (
    reprogramacion_id INT IDENTITY(1,1) PRIMARY KEY,
    solicitud_id INT NOT NULL,
    fecha_solicitada DATE NOT NULL,
    hora_solicitada TIME NOT NULL,
    motivo VARCHAR(350) NULL,
    estado VARCHAR(20) NOT NULL DEFAULT 'Pendiente',
    fecha_solicitud DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT FK_Reprogramacion_Solicitud FOREIGN KEY (solicitud_id)
        REFERENCES SolicitudCita(solicitud_id),
    CONSTRAINT CK_Reprogramacion_Estado CHECK (estado IN ('Pendiente', 'Aprobada', 'Rechazada'))
);
GO

CREATE TABLE HistorialEstadoCita (
    historial_id INT IDENTITY(1,1) PRIMARY KEY,
    cita_id INT NULL,
    solicitud_id INT NOT NULL,
    estado_anterior VARCHAR(30) NULL,
    estado_nuevo VARCHAR(30) NOT NULL,
    cambiado_por VARCHAR(120) NOT NULL,
    observacion VARCHAR(500) NULL,
    fecha_cambio DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT FK_Historial_Cita FOREIGN KEY (cita_id)
        REFERENCES Cita(cita_id),
    CONSTRAINT FK_Historial_Solicitud FOREIGN KEY (solicitud_id)
        REFERENCES SolicitudCita(solicitud_id)
);
GO

CREATE TABLE BitacoraSistema (
    bitacora_id INT IDENTITY(1,1) PRIMARY KEY,
    tabla_afectada VARCHAR(80) NOT NULL,
    registro_id INT NOT NULL,
    accion VARCHAR(20) NOT NULL,
    descripcion VARCHAR(500) NULL,
    usuario_bd SYSNAME NOT NULL DEFAULT SUSER_SNAME(),
    fecha_accion DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT CK_Bitacora_Accion CHECK (accion IN ('INSERT', 'UPDATE', 'DELETE'))
);
GO

CREATE INDEX IX_Solicitud_Estado ON SolicitudCita(estado);
CREATE INDEX IX_Solicitud_Codigo ON SolicitudCita(codigo_seguimiento);
CREATE INDEX IX_Cita_Doctor_Fecha ON Cita(doctor_id, fecha_cita);
CREATE INDEX IX_Reprogramacion_Estado ON SolicitudReprogramacion(estado);
CREATE INDEX IX_Bitacora_Tabla_Fecha ON BitacoraSistema(tabla_afectada, fecha_accion DESC);
GO

INSERT INTO ConfiguracionSistema (nombre, valor, descripcion) VALUES
('DuracionCitaMinutos', '30', 'Cantidad de tiempo X que dura cada cita médica en minutos');
GO

-- En una aplicación real se guarda un hash creado por backend, no la contraseña en texto plano.
INSERT INTO UsuarioSistema (usuario, clave_hash, rol) VALUES
('admin', 'HASH_DEMO_Seguro123', 'Administrador');
GO

INSERT INTO Hospital (nombre, direccion, telefono) VALUES
('Hospital Central del Seguro', 'Vía España, Ciudad de Panamá', '6000-2000'),
('Policlínica Norte', 'Transístmica', '6000-2100'),
('Hospital Pediátrico Vida', 'San Miguelito', '6000-2200');
GO

INSERT INTO Especialidad (nombre, descripcion) VALUES
('Medicina General', 'Atención general y diagnósticos iniciales'),
('Cardiología', 'Atención de enfermedades del corazón'),
('Pediatría', 'Atención médica para niños'),
('Ortopedia', 'Atención de huesos, músculos y articulaciones'),
('Dermatología', 'Atención de piel, cabello y uñas'),
('Neurología', 'Atención del sistema nervioso');
GO

INSERT INTO Doctor (hospital_id, especialidad_id, nombre_completo, consultorio, correo) VALUES
(1, 1, 'Dra. Laura Sánchez', 'Consultorio 101', 'laura.sanchez@seguro.com'),
(1, 2, 'Dr. Marcos Herrera', 'Consultorio 204', 'marcos.herrera@seguro.com'),
(3, 3, 'Dra. Valeria Castillo', 'Consultorio 108', 'valeria.castillo@seguro.com'),
(2, 4, 'Dr. Andrés Morales', 'Consultorio 303', 'andres.morales@seguro.com'),
(1, 5, 'Dra. Camila Reyes', 'Consultorio 210', 'camila.reyes@seguro.com'),
(2, 6, 'Dr. Ricardo Gómez', 'Consultorio 402', 'ricardo.gomez@seguro.com');
GO

CREATE VIEW vw_SolicitudesRecepcion AS
SELECT
    sc.solicitud_id,
    sc.codigo_seguimiento,
    p.identificacion,
    p.nombre_completo AS paciente,
    p.telefono,
    h.nombre AS hospital,
    e.nombre AS especialidad,
    sc.motivo,
    sc.prioridad,
    sc.fecha_preferida,
    sc.hora_preferida,
    sc.solicitado_por,
    sc.estado,
    sr.fecha_solicitada AS nueva_fecha_solicitada,
    sr.hora_solicitada AS nueva_hora_solicitada,
    sr.motivo AS motivo_reprogramacion,
    sc.fecha_solicitud
FROM SolicitudCita sc
INNER JOIN Paciente p ON p.paciente_id = sc.paciente_id
INNER JOIN Hospital h ON h.hospital_id = sc.hospital_id
INNER JOIN Especialidad e ON e.especialidad_id = sc.especialidad_id
LEFT JOIN SolicitudReprogramacion sr
    ON sr.solicitud_id = sc.solicitud_id
   AND sr.estado = 'Pendiente';
GO

CREATE VIEW vw_CitasDoctor AS
SELECT
    c.cita_id,
    sc.codigo_seguimiento,
    p.nombre_completo AS paciente,
    p.identificacion,
    p.telefono,
    h.nombre AS hospital,
    e.nombre AS especialidad,
    d.nombre_completo AS doctor,
    d.consultorio,
    c.fecha_cita,
    c.hora_cita,
    c.duracion_minutos,
    DATEADD(MINUTE, c.duracion_minutos,
        DATEADD(MINUTE, DATEDIFF(MINUTE, CAST('00:00' AS TIME), c.hora_cita), CAST(c.fecha_cita AS DATETIME2))
    ) AS fecha_hora_fin,
    c.estado,
    c.observacion,
    c.fecha_asignacion
FROM Cita c
INNER JOIN SolicitudCita sc ON sc.solicitud_id = c.solicitud_id
INNER JOIN Paciente p ON p.paciente_id = sc.paciente_id
INNER JOIN Doctor d ON d.doctor_id = c.doctor_id
INNER JOIN Hospital h ON h.hospital_id = d.hospital_id
INNER JOIN Especialidad e ON e.especialidad_id = d.especialidad_id;
GO

CREATE VIEW vw_DashboardEstados AS
SELECT estado, COUNT(*) AS total
FROM SolicitudCita
GROUP BY estado;
GO

CREATE FUNCTION fn_DoctorDisponible(
    @doctor_id INT,
    @fecha DATE,
    @hora TIME,
    @duracion_minutos INT,
    @cita_ignorar_id INT = NULL
)
RETURNS BIT
AS
BEGIN
    DECLARE @disponible BIT = 1;
    DECLARE @inicio_nuevo DATETIME2 = DATEADD(MINUTE, DATEDIFF(MINUTE, CAST('00:00' AS TIME), @hora), CAST(@fecha AS DATETIME2));
    DECLARE @fin_nuevo DATETIME2 = DATEADD(MINUTE, @duracion_minutos, @inicio_nuevo);

    IF EXISTS (
        SELECT 1
        FROM Cita c
        WHERE c.doctor_id = @doctor_id
          AND c.fecha_cita = @fecha
          AND c.estado IN ('Asignada', 'Confirmada')
          AND (@cita_ignorar_id IS NULL OR c.cita_id <> @cita_ignorar_id)
          AND @inicio_nuevo < DATEADD(MINUTE, c.duracion_minutos,
                DATEADD(MINUTE, DATEDIFF(MINUTE, CAST('00:00' AS TIME), c.hora_cita), CAST(c.fecha_cita AS DATETIME2))
              )
          AND DATEADD(MINUTE, DATEDIFF(MINUTE, CAST('00:00' AS TIME), c.hora_cita), CAST(c.fecha_cita AS DATETIME2)) < @fin_nuevo
    )
        SET @disponible = 0;

    RETURN @disponible;
END;
GO

CREATE PROCEDURE sp_ActualizarDuracionCita
    @duracion_minutos INT
AS
BEGIN
    SET NOCOUNT ON;

    IF @duracion_minutos < 5 OR @duracion_minutos > 240
        THROW 50010, 'La duración debe estar entre 5 y 240 minutos.', 1;

    UPDATE ConfiguracionSistema
    SET valor = CAST(@duracion_minutos AS VARCHAR(80)),
        fecha_actualizacion = SYSDATETIME()
    WHERE nombre = 'DuracionCitaMinutos';
END;
GO

CREATE PROCEDURE sp_CrearHospital
    @nombre VARCHAR(120),
    @direccion VARCHAR(250),
    @telefono VARCHAR(25)
AS
BEGIN
    INSERT INTO Hospital (nombre, direccion, telefono)
    VALUES (@nombre, @direccion, @telefono);

    SELECT SCOPE_IDENTITY() AS hospital_id;
END;
GO

CREATE PROCEDURE sp_CrearEspecialidad
    @nombre VARCHAR(80),
    @descripcion VARCHAR(250) = NULL
AS
BEGIN
    INSERT INTO Especialidad (nombre, descripcion)
    VALUES (@nombre, @descripcion);

    SELECT SCOPE_IDENTITY() AS especialidad_id;
END;
GO

CREATE PROCEDURE sp_CrearDoctor
    @hospital_id INT,
    @especialidad_id INT,
    @nombre_completo VARCHAR(120),
    @consultorio VARCHAR(40),
    @correo VARCHAR(120) = NULL
AS
BEGIN
    INSERT INTO Doctor (hospital_id, especialidad_id, nombre_completo, consultorio, correo)
    VALUES (@hospital_id, @especialidad_id, @nombre_completo, @consultorio, @correo);

    SELECT SCOPE_IDENTITY() AS doctor_id;
END;
GO

CREATE PROCEDURE sp_CrearSolicitudPublica
    @identificacion VARCHAR(30),
    @nombre_completo VARCHAR(120),
    @telefono VARCHAR(25),
    @correo VARCHAR(120) = NULL,
    @hospital_id INT,
    @especialidad_id INT,
    @motivo VARCHAR(500),
    @prioridad VARCHAR(15),
    @fecha_preferida DATE,
    @hora_preferida TIME,
    @solicitado_por VARCHAR(120)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @paciente_id INT;
    DECLARE @codigo VARCHAR(20) = CONCAT('CITA-', UPPER(LEFT(REPLACE(CONVERT(VARCHAR(36), NEWID()), '-', ''), 6)));

    SELECT @paciente_id = paciente_id
    FROM Paciente
    WHERE identificacion = @identificacion;

    IF @paciente_id IS NULL
    BEGIN
        INSERT INTO Paciente (identificacion, nombre_completo, telefono, correo)
        VALUES (@identificacion, @nombre_completo, @telefono, @correo);

        SET @paciente_id = SCOPE_IDENTITY();
    END
    ELSE
    BEGIN
        UPDATE Paciente
        SET nombre_completo = @nombre_completo,
            telefono = @telefono,
            correo = @correo
        WHERE paciente_id = @paciente_id;
    END

    INSERT INTO SolicitudCita (
        codigo_seguimiento,
        paciente_id,
        hospital_id,
        especialidad_id,
        motivo,
        prioridad,
        fecha_preferida,
        hora_preferida,
        solicitado_por
    )
    VALUES (
        @codigo,
        @paciente_id,
        @hospital_id,
        @especialidad_id,
        @motivo,
        @prioridad,
        @fecha_preferida,
        @hora_preferida,
        @solicitado_por
    );

    SELECT SCOPE_IDENTITY() AS solicitud_id, @codigo AS codigo_seguimiento;
END;
GO

CREATE PROCEDURE sp_CancelarCitaPublica
    @codigo_seguimiento VARCHAR(20),
    @identificacion VARCHAR(30)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRANSACTION;

    DECLARE @solicitud_id INT;
    DECLARE @cita_id INT;
    DECLARE @estado_anterior VARCHAR(30);

    SELECT
        @solicitud_id = sc.solicitud_id,
        @estado_anterior = sc.estado
    FROM SolicitudCita sc
    INNER JOIN Paciente p ON p.paciente_id = sc.paciente_id
    WHERE sc.codigo_seguimiento = @codigo_seguimiento
      AND p.identificacion = @identificacion;

    IF @solicitud_id IS NULL
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50020, 'No existe una cita con ese código e identificación.', 1;
    END

    IF EXISTS (SELECT 1 FROM Cita WHERE solicitud_id = @solicitud_id AND estado = 'Atendida')
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50021, 'Una cita atendida no puede cancelarse desde la parte pública.', 1;
    END

    SELECT @cita_id = cita_id FROM Cita WHERE solicitud_id = @solicitud_id;

    UPDATE SolicitudCita
    SET estado = 'Cancelada'
    WHERE solicitud_id = @solicitud_id;

    IF @cita_id IS NOT NULL
    BEGIN
        UPDATE Cita
        SET estado = 'Cancelada',
            observacion = 'Cancelada por usuario público'
        WHERE cita_id = @cita_id;
    END

    INSERT INTO HistorialEstadoCita (cita_id, solicitud_id, estado_anterior, estado_nuevo, cambiado_por, observacion)
    VALUES (@cita_id, @solicitud_id, @estado_anterior, 'Cancelada', 'Usuario público', 'Cancelación solicitada desde la página pública');

    COMMIT TRANSACTION;
END;
GO

CREATE PROCEDURE sp_SolicitarReprogramacionPublica
    @codigo_seguimiento VARCHAR(20),
    @identificacion VARCHAR(30),
    @fecha_solicitada DATE,
    @hora_solicitada TIME,
    @motivo VARCHAR(350) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRANSACTION;

    DECLARE @solicitud_id INT;
    DECLARE @estado_anterior VARCHAR(30);

    SELECT
        @solicitud_id = sc.solicitud_id,
        @estado_anterior = sc.estado
    FROM SolicitudCita sc
    INNER JOIN Paciente p ON p.paciente_id = sc.paciente_id
    WHERE sc.codigo_seguimiento = @codigo_seguimiento
      AND p.identificacion = @identificacion
      AND sc.estado <> 'Cancelada';

    IF @solicitud_id IS NULL
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50030, 'No existe una cita activa con ese código e identificación.', 1;
    END

    INSERT INTO SolicitudReprogramacion (solicitud_id, fecha_solicitada, hora_solicitada, motivo)
    VALUES (@solicitud_id, @fecha_solicitada, @hora_solicitada, @motivo);

    UPDATE SolicitudCita
    SET estado = 'ReprogramacionSolicitada'
    WHERE solicitud_id = @solicitud_id;

    INSERT INTO HistorialEstadoCita (solicitud_id, estado_anterior, estado_nuevo, cambiado_por, observacion)
    VALUES (@solicitud_id, @estado_anterior, 'ReprogramacionSolicitada', 'Usuario público', @motivo);

    COMMIT TRANSACTION;
END;
GO

CREATE PROCEDURE sp_AsignarDoctorACita
    @solicitud_id INT,
    @doctor_id INT,
    @fecha_cita DATE,
    @hora_cita TIME,
    @asignado_por VARCHAR(120),
    @duracion_minutos INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRANSACTION;

    DECLARE @hospital_id INT;
    DECLARE @especialidad_id INT;
    DECLARE @estado_anterior VARCHAR(30);
    DECLARE @cita_id INT;

    IF @duracion_minutos IS NULL
    BEGIN
        SELECT @duracion_minutos = CAST(valor AS INT)
        FROM ConfiguracionSistema
        WHERE nombre = 'DuracionCitaMinutos';
    END

    SELECT
        @hospital_id = hospital_id,
        @especialidad_id = especialidad_id,
        @estado_anterior = estado
    FROM SolicitudCita WITH (UPDLOCK, ROWLOCK)
    WHERE solicitud_id = @solicitud_id
      AND estado IN ('Pendiente', 'Asignada', 'ReprogramacionSolicitada');

    IF @hospital_id IS NULL
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50040, 'La solicitud no existe o no puede ser asignada.', 1;
    END

    IF NOT EXISTS (
        SELECT 1
        FROM Doctor
        WHERE doctor_id = @doctor_id
          AND hospital_id = @hospital_id
          AND especialidad_id = @especialidad_id
          AND activo = 1
    )
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50041, 'El doctor no pertenece al hospital y especialidad solicitados.', 1;
    END

    SELECT @cita_id = cita_id
    FROM Cita
    WHERE solicitud_id = @solicitud_id;

    IF dbo.fn_DoctorDisponible(@doctor_id, @fecha_cita, @hora_cita, @duracion_minutos, @cita_id) = 0
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50042, 'El doctor no está disponible en esa ventana de tiempo.', 1;
    END

    IF @cita_id IS NULL
    BEGIN
        INSERT INTO Cita (solicitud_id, doctor_id, fecha_cita, hora_cita, duracion_minutos, estado, observacion)
        VALUES (@solicitud_id, @doctor_id, @fecha_cita, @hora_cita, @duracion_minutos, 'Asignada', CONCAT('Asignada por ', @asignado_por));

        SET @cita_id = SCOPE_IDENTITY();
    END
    ELSE
    BEGIN
        UPDATE Cita
        SET doctor_id = @doctor_id,
            fecha_cita = @fecha_cita,
            hora_cita = @hora_cita,
            duracion_minutos = @duracion_minutos,
            estado = 'Asignada',
            observacion = CONCAT('Actualizada por ', @asignado_por)
        WHERE cita_id = @cita_id;
    END

    UPDATE SolicitudCita
    SET estado = 'Asignada'
    WHERE solicitud_id = @solicitud_id;

    UPDATE SolicitudReprogramacion
    SET estado = 'Aprobada'
    WHERE solicitud_id = @solicitud_id
      AND estado = 'Pendiente';

    INSERT INTO HistorialEstadoCita (cita_id, solicitud_id, estado_anterior, estado_nuevo, cambiado_por)
    VALUES (@cita_id, @solicitud_id, @estado_anterior, 'Asignada', @asignado_por);

    COMMIT TRANSACTION;
END;
GO

CREATE PROCEDURE sp_ActualizarEstadoCita
    @cita_id INT,
    @estado_nuevo VARCHAR(20),
    @observacion VARCHAR(500) = NULL,
    @cambiado_por VARCHAR(120)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRANSACTION;

    DECLARE @estado_anterior VARCHAR(20);
    DECLARE @solicitud_id INT;

    SELECT
        @estado_anterior = estado,
        @solicitud_id = solicitud_id
    FROM Cita
    WHERE cita_id = @cita_id;

    IF @estado_anterior IS NULL
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50050, 'La cita no existe.', 1;
    END

    UPDATE Cita
    SET estado = @estado_nuevo,
        observacion = COALESCE(@observacion, observacion)
    WHERE cita_id = @cita_id;

    IF @estado_nuevo = 'Cancelada'
        UPDATE SolicitudCita SET estado = 'Cancelada' WHERE solicitud_id = @solicitud_id;

    INSERT INTO HistorialEstadoCita (cita_id, solicitud_id, estado_anterior, estado_nuevo, cambiado_por, observacion)
    VALUES (@cita_id, @solicitud_id, @estado_anterior, @estado_nuevo, @cambiado_por, @observacion);

    COMMIT TRANSACTION;
END;
GO

/* TRIGGERS */

CREATE TRIGGER trg_Cita_ValidarTraslape
ON Cita
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (
        SELECT 1
        FROM inserted i
        INNER JOIN Cita c
            ON c.doctor_id = i.doctor_id
           AND c.fecha_cita = i.fecha_cita
           AND c.cita_id <> i.cita_id
           AND c.estado IN ('Asignada', 'Confirmada')
           AND i.estado IN ('Asignada', 'Confirmada')
           AND DATEADD(MINUTE, DATEDIFF(MINUTE, CAST('00:00' AS TIME), i.hora_cita), CAST(i.fecha_cita AS DATETIME2))
                < DATEADD(MINUTE, c.duracion_minutos,
                    DATEADD(MINUTE, DATEDIFF(MINUTE, CAST('00:00' AS TIME), c.hora_cita), CAST(c.fecha_cita AS DATETIME2))
                  )
           AND DATEADD(MINUTE, DATEDIFF(MINUTE, CAST('00:00' AS TIME), c.hora_cita), CAST(c.fecha_cita AS DATETIME2))
                < DATEADD(MINUTE, i.duracion_minutos,
                    DATEADD(MINUTE, DATEDIFF(MINUTE, CAST('00:00' AS TIME), i.hora_cita), CAST(i.fecha_cita AS DATETIME2))
                  )
    )
    BEGIN
        THROW 50100, 'No se puede guardar la cita porque se cruza con otra cita activa del mismo doctor.', 1;
    END
END;
GO

CREATE TRIGGER trg_Cita_Bitacora
ON Cita
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO BitacoraSistema (tabla_afectada, registro_id, accion, descripcion)
    SELECT 'Cita', i.cita_id, 'INSERT', CONCAT('Cita creada para solicitud ', i.solicitud_id)
    FROM inserted i
    LEFT JOIN deleted d ON d.cita_id = i.cita_id
    WHERE d.cita_id IS NULL;

    INSERT INTO BitacoraSistema (tabla_afectada, registro_id, accion, descripcion)
    SELECT 'Cita', i.cita_id, 'UPDATE', CONCAT('Cita actualizada. Estado: ', i.estado)
    FROM inserted i
    INNER JOIN deleted d ON d.cita_id = i.cita_id;

    INSERT INTO BitacoraSistema (tabla_afectada, registro_id, accion, descripcion)
    SELECT 'Cita', d.cita_id, 'DELETE', CONCAT('Cita eliminada de solicitud ', d.solicitud_id)
    FROM deleted d
    LEFT JOIN inserted i ON i.cita_id = d.cita_id
    WHERE i.cita_id IS NULL;
END;
GO

CREATE TRIGGER trg_Doctor_Bitacora
ON Doctor
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO BitacoraSistema (tabla_afectada, registro_id, accion, descripcion)
    SELECT 'Doctor', i.doctor_id, 'INSERT', CONCAT('Doctor creado: ', i.nombre_completo)
    FROM inserted i
    LEFT JOIN deleted d ON d.doctor_id = i.doctor_id
    WHERE d.doctor_id IS NULL;

    INSERT INTO BitacoraSistema (tabla_afectada, registro_id, accion, descripcion)
    SELECT 'Doctor', i.doctor_id, 'UPDATE', CONCAT('Doctor actualizado: ', i.nombre_completo)
    FROM inserted i
    INNER JOIN deleted d ON d.doctor_id = i.doctor_id;
END;
GO

CREATE TRIGGER trg_Hospital_Bitacora
ON Hospital
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO BitacoraSistema (tabla_afectada, registro_id, accion, descripcion)
    SELECT 'Hospital', i.hospital_id, 'INSERT', CONCAT('Hospital creado: ', i.nombre)
    FROM inserted i
    LEFT JOIN deleted d ON d.hospital_id = i.hospital_id
    WHERE d.hospital_id IS NULL;

    INSERT INTO BitacoraSistema (tabla_afectada, registro_id, accion, descripcion)
    SELECT 'Hospital', i.hospital_id, 'UPDATE', CONCAT('Hospital actualizado: ', i.nombre)
    FROM inserted i
    INNER JOIN deleted d ON d.hospital_id = i.hospital_id;
END;
GO

CREATE TRIGGER trg_Especialidad_Bitacora
ON Especialidad
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO BitacoraSistema (tabla_afectada, registro_id, accion, descripcion)
    SELECT 'Especialidad', i.especialidad_id, 'INSERT', CONCAT('Especialidad creada: ', i.nombre)
    FROM inserted i
    LEFT JOIN deleted d ON d.especialidad_id = i.especialidad_id
    WHERE d.especialidad_id IS NULL;

    INSERT INTO BitacoraSistema (tabla_afectada, registro_id, accion, descripcion)
    SELECT 'Especialidad', i.especialidad_id, 'UPDATE', CONCAT('Especialidad actualizada: ', i.nombre)
    FROM inserted i
    INNER JOIN deleted d ON d.especialidad_id = i.especialidad_id;
END;
GO

CREATE TRIGGER trg_Configuracion_Bitacora
ON ConfiguracionSistema
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO BitacoraSistema (tabla_afectada, registro_id, accion, descripcion)
    SELECT 'ConfiguracionSistema', i.configuracion_id, 'UPDATE',
           CONCAT('Configuración actualizada: ', i.nombre, ' = ', i.valor)
    FROM inserted i;
END;
GO

/* Datos de prueba */
EXEC sp_CrearSolicitudPublica
    @identificacion = '8-111-222',
    @nombre_completo = 'María Torres',
    @telefono = '6123-4567',
    @correo = 'maria@email.com',
    @hospital_id = 1,
    @especialidad_id = 2,
    @motivo = 'Dolor en el pecho y presión alta en los últimos días.',
    @prioridad = 'Alta',
    @fecha_preferida = '2026-06-25',
    @hora_preferida = '09:30',
    @solicitado_por = 'Luis Torres, hijo';
GO

EXEC sp_CrearSolicitudPublica
    @identificacion = '4-555-888',
    @nombre_completo = 'Daniel Ríos',
    @telefono = '6780-1200',
    @correo = NULL,
    @hospital_id = 3,
    @especialidad_id = 3,
    @motivo = 'Control general y revisión de vacunas.',
    @prioridad = 'Normal',
    @fecha_preferida = '2026-06-26',
    @hora_preferida = '14:00',
    @solicitado_por = 'Ana Ríos, madre';
GO

EXEC sp_AsignarDoctorACita
    @solicitud_id = 2,
    @doctor_id = 3,
    @fecha_cita = '2026-06-26',
    @hora_cita = '14:00',
    @asignado_por = 'admin',
    @duracion_minutos = 30;
GO


SELECT * FROM vw_SolicitudesRecepcion;
SELECT * FROM vw_CitasDoctor;
SELECT * FROM vw_DashboardEstados;
GO
/*Por dios alguien lee esto? XD */