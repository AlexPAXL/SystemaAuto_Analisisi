-- ═══════════════════════════════════════════════════════════════════════════
--  init.sql — Esquema de base de datos para automatizacion Académica
--
--  Este archivo se ejecuta AUTOMÁTICAMENTE en el primer arranque de
--  PostgreSQL (montado en /docker-entrypoint-initdb.d/).
--
--  Tablas:
--    1. attendance          — Registros de asistencia
--    2. task_submissions    — Entregas de tareas
--    3. feedback            — Retroalimentación y calificaciones
--    4. reports             — Log de reportes generados
--    5. error_logs          — Registro de errores de workflows
--    6. notifications_log   — Log de notificaciones enviadas
-- ═══════════════════════════════════════════════════════════════════════════

-- ─── Extensiones útiles ──────────────────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ─── 1. Tabla de Asistencia ───────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS attendance (
    id           SERIAL PRIMARY KEY,
    student_id   VARCHAR(30)  NOT NULL,
    student_name VARCHAR(120) NOT NULL,
    course_id    VARCHAR(30)  NOT NULL,
    date         DATE         NOT NULL,
    status       VARCHAR(10)  NOT NULL
                   CHECK (status IN ('present', 'absent', 'late', 'excused')),
    processed_at TIMESTAMP    NOT NULL DEFAULT NOW(),
    UNIQUE (student_id, course_id, date)   -- evita duplicados por import repetido
);

CREATE INDEX IF NOT EXISTS idx_att_course_date   ON attendance (course_id, date);
CREATE INDEX IF NOT EXISTS idx_att_student       ON attendance (student_id);
CREATE INDEX IF NOT EXISTS idx_att_status        ON attendance (status);

-- ─── 2. Tabla de Entregas de Tareas ──────────────────────────────────────────
CREATE TABLE IF NOT EXISTS task_submissions (
    id               SERIAL PRIMARY KEY,
    student_id       VARCHAR(30)  NOT NULL,
    student_name     VARCHAR(120),
    task_id          VARCHAR(30)  NOT NULL,
    task_name        VARCHAR(200),
    submission_date  TIMESTAMP,
    deadline         TIMESTAMP,
    status           VARCHAR(20)  NOT NULL
                       CHECK (status IN ('on_time','late','missing','invalid_format')),
    file_name        VARCHAR(200),
    file_extension   VARCHAR(15),
    is_late          BOOLEAN      NOT NULL DEFAULT FALSE,
    created_at       TIMESTAMP    NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_sub_task     ON task_submissions (task_id);
CREATE INDEX IF NOT EXISTS idx_sub_student  ON task_submissions (student_id);
CREATE INDEX IF NOT EXISTS idx_sub_status   ON task_submissions (status);
CREATE INDEX IF NOT EXISTS idx_sub_late     ON task_submissions (is_late);

-- ─── 3. Tabla de Retroalimentación ───────────────────────────────────────────
CREATE TABLE IF NOT EXISTS feedback (
    id                SERIAL PRIMARY KEY,
    student_id        VARCHAR(30)   NOT NULL,
    student_name      VARCHAR(120),
    course_id         VARCHAR(30),
    task_id           VARCHAR(30),
    grade             DECIMAL(5,2)  CHECK (grade >= 0 AND grade <= 100),
    feedback_text     TEXT,
    feedback_type     VARCHAR(20)
                        CHECK (feedback_type IN ('positive','neutral','negative')),
    sent_notification BOOLEAN       NOT NULL DEFAULT FALSE,
    created_at        TIMESTAMP     NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_fb_student   ON feedback (student_id);
CREATE INDEX IF NOT EXISTS idx_fb_course    ON feedback (course_id);
CREATE INDEX IF NOT EXISTS idx_fb_grade     ON feedback (grade);

-- ─── 4. Tabla de Reportes Generados ──────────────────────────────────────────
CREATE TABLE IF NOT EXISTS reports (
    id            SERIAL PRIMARY KEY,
    report_type   VARCHAR(60)   NOT NULL,
    course_id     VARCHAR(30),
    generated_at  TIMESTAMP     NOT NULL DEFAULT NOW(),
    file_path     VARCHAR(400),
    status        VARCHAR(20)   NOT NULL DEFAULT 'generated'
                    CHECK (status IN ('generated','failed','archived')),
    records_count INTEGER       DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_rpt_type ON reports (report_type);
CREATE INDEX IF NOT EXISTS idx_rpt_date ON reports (generated_at);

-- ─── 5. Tabla de Log de Errores ───────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS error_logs (
    id             SERIAL PRIMARY KEY,
    workflow_name  VARCHAR(120),
    node_name      VARCHAR(120),
    error_message  TEXT,
    error_data     JSONB,
    created_at     TIMESTAMP    NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_err_workflow ON error_logs (workflow_name);
CREATE INDEX IF NOT EXISTS idx_err_date     ON error_logs (created_at DESC);

-- ─── 6. Tabla de Log de Notificaciones ───────────────────────────────────────
CREATE TABLE IF NOT EXISTS notifications_log (
    id                SERIAL PRIMARY KEY,
    student_id        VARCHAR(30),
    notification_type VARCHAR(60),
    message           TEXT,
    status            VARCHAR(20) NOT NULL DEFAULT 'sent'
                        CHECK (status IN ('sent','failed','pending')),
    created_at        TIMESTAMP   NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_notif_student ON notifications_log (student_id);
CREATE INDEX IF NOT EXISTS idx_notif_type    ON notifications_log (notification_type);

-- ─── 7. Tabla de Tareas (habilitadas por el profesor) ────────────────────────
CREATE TABLE IF NOT EXISTS tasks (
    id            SERIAL PRIMARY KEY,
    task_id       VARCHAR(30)  NOT NULL UNIQUE,
    task_name     VARCHAR(200) NOT NULL,
    course_id     VARCHAR(30)  NOT NULL,
    deadline      TIMESTAMP    NOT NULL,
    allowed_exts  TEXT         NOT NULL DEFAULT 'pdf,docx,xlsx,zip,py,java,cpp,txt',
    is_open       BOOLEAN      NOT NULL DEFAULT TRUE,
    created_by    VARCHAR(120),
    created_at    TIMESTAMP    NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_tasks_course ON tasks (course_id);
CREATE INDEX IF NOT EXISTS idx_tasks_open   ON tasks (is_open);

-- ═══════════════════════════════════════════════════════════════════════════
--  Datos de prueba / seed data
-- ═══════════════════════════════════════════════════════════════════════════

-- Tareas de muestra (habilitadas por el profesor)
INSERT INTO tasks (task_id, task_name, course_id, deadline, allowed_exts, is_open, created_by) VALUES
  ('TASK01', 'Proyecto Final Fase 1', 'CS101', '2025-12-15 23:59:00', 'pdf,docx', TRUE,  'PROF01'),
  ('TASK02', 'Análisis de Datos',     'CS102', '2025-12-22 23:59:00', 'xlsx,pdf', TRUE,  'PROF01'),
  ('TASK03', 'Laboratorio de Redes',  'CS103', '2026-01-10 23:59:00', 'pdf,zip',  TRUE,  'PROF02')
ON CONFLICT DO NOTHING;

-- Asistencia de muestra (espejo del CSV de prueba)
INSERT INTO attendance (student_id, student_name, course_id, date, status) VALUES
  ('STU001', 'María García',      'CS101', '2024-01-15', 'present'),
  ('STU002', 'Carlos López',      'CS101', '2024-01-15', 'absent'),
  ('STU003', 'Ana Martínez',      'CS101', '2024-01-15', 'late'),
  ('STU004', 'Pedro Rodríguez',   'CS101', '2024-01-15', 'present'),
  ('STU005', 'Laura Pérez',       'CS101', '2024-01-15', 'excused'),
  ('STU006', 'Roberto Sánchez',   'CS102', '2024-01-15', 'present'),
  ('STU007', 'Sofía González',    'CS102', '2024-01-15', 'present'),
  ('STU008', 'Diego Torres',      'CS102', '2024-01-15', 'absent'),
  ('STU009', 'Valentina Flores',  'CS102', '2024-01-15', 'late'),
  ('STU010', 'Andrés Ramírez',    'CS103', '2024-01-15', 'present')
ON CONFLICT (student_id, course_id, date) DO NOTHING;

-- Entregas de muestra
INSERT INTO task_submissions (student_id, student_name, task_id, task_name, submission_date, deadline, status, file_name, file_extension, is_late) VALUES
  ('STU001', 'Ana Maria',    'TASK01', 'Proyecto Final Fase 1', '2024-01-14 23:00:00', '2024-01-15 23:59:00', 'on_time',       'tarea1_maria',    'pdf',  FALSE),
  ('STU002', 'Carlos López',   'TASK01', 'Proyecto Final Fase 1', '2024-01-16 10:30:00', '2024-01-15 23:59:00', 'late',          'tarea1_carlos',   'pdf',  TRUE),
  ('STU003', 'Ana Martínez',   'TASK01', 'Proyecto Final Fase 1', '2024-01-15 20:00:00', '2024-01-15 23:59:00', 'on_time',       'tarea1_ana',      'docx', FALSE),
  ('STU004', 'Pedro Rodríguez','TASK01', 'Proyecto Final Fase 1', '2024-01-15 22:45:00', '2024-01-15 23:59:00', 'on_time',       'tarea1_pedro',    'pdf',  FALSE),
  ('STU005', 'Laura Pérez',    'TASK01', 'Proyecto Final Fase 1', '2024-01-17 09:00:00', '2024-01-15 23:59:00', 'late',          'tarea1_laura',    'pdf',  TRUE),
  ('STU006', 'Roberto Sánchez','TASK02', 'Análisis de Datos',     '2024-01-20 14:00:00', '2024-01-22 23:59:00', 'on_time',       'analisis_roberto','xlsx', FALSE),
  ('STU007', 'Sofía González', 'TASK02', 'Análisis de Datos',     '2024-01-23 08:00:00', '2024-01-22 23:59:00', 'late',          'analisis_sofia',  'xlsx', TRUE),
  ('STU008', 'Diego Torres',   'TASK02', 'Análisis de Datos',     NULL,                  '2024-01-22 23:59:00', 'missing',       NULL,              NULL,   FALSE)
ON CONFLICT DO NOTHING;

-- Retroalimentación de muestra
INSERT INTO feedback (student_id, student_name, course_id, task_id, grade, feedback_text, feedback_type, sent_notification) VALUES
  ('STU001', 'María García',    'CS101', 'TASK01', 92.5, 'Excelente trabajo. Documentación clara y código bien estructurado.',        'positive', TRUE),
  ('STU002', 'Carlos López',   'CS101', 'TASK01', 55.0, 'Entrega tardía con penalización. Falta documentación. Revisar estructura.',  'negative', TRUE),
  ('STU003', 'Ana Martínez',   'CS101', 'TASK01', 78.0, 'Buen esfuerzo. Mejorar la sección de conclusiones y pruebas unitarias.',    'neutral',  TRUE),
  ('STU004', 'Pedro Rodríguez','CS101', 'TASK01', 85.0, 'Muy buen trabajo. Código limpio y bien comentado.',                         'positive', FALSE),
  ('STU005', 'Laura Pérez',    'CS101', 'TASK01', 48.0, 'Entrega con dos días de atraso. Contenido incompleto. Requiere reentrega.', 'negative', TRUE)
ON CONFLICT DO NOTHING;

-- ═══════════════════════════════════════════════════════════════════════════
--  Vista útil para reportes
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE VIEW vw_attendance_summary AS
SELECT
    course_id,
    date,
    COUNT(*)                                                           AS total_students,
    SUM(CASE WHEN status = 'present' THEN 1 ELSE 0 END)               AS present_count,
    SUM(CASE WHEN status = 'absent'  THEN 1 ELSE 0 END)               AS absent_count,
    SUM(CASE WHEN status = 'late'    THEN 1 ELSE 0 END)               AS late_count,
    SUM(CASE WHEN status = 'excused' THEN 1 ELSE 0 END)               AS excused_count,
    ROUND(SUM(CASE WHEN status='present' THEN 1 ELSE 0 END)*100.0 /
          NULLIF(COUNT(*),0), 1)                                       AS attendance_rate_pct
FROM attendance
GROUP BY course_id, date
ORDER BY course_id, date;

CREATE OR REPLACE VIEW vw_task_summary AS
SELECT
    task_id,
    task_name,
    COUNT(*)                                                           AS total_submissions,
    SUM(CASE WHEN status = 'on_time'       THEN 1 ELSE 0 END)         AS on_time_count,
    SUM(CASE WHEN is_late                  THEN 1 ELSE 0 END)         AS late_count,
    SUM(CASE WHEN status = 'missing'       THEN 1 ELSE 0 END)         AS missing_count,
    SUM(CASE WHEN status = 'invalid_format'THEN 1 ELSE 0 END)         AS invalid_count,
    ROUND(SUM(CASE WHEN is_late THEN 1 ELSE 0 END)*100.0 /
          NULLIF(COUNT(*),0), 1)                                       AS late_rate_pct
FROM task_submissions
GROUP BY task_id, task_name
ORDER BY task_id;

CREATE OR REPLACE VIEW vw_grade_summary AS
SELECT
    course_id,
    task_id,
    COUNT(*)                                                           AS total_graded,
    ROUND(AVG(grade),2)                                                AS avg_grade,
    MIN(grade)                                                         AS min_grade,
    MAX(grade)                                                         AS max_grade,
    SUM(CASE WHEN grade >= 60 THEN 1 ELSE 0 END)                      AS passing_count,
    SUM(CASE WHEN grade <  60 THEN 1 ELSE 0 END)                      AS failing_count
FROM feedback
WHERE grade IS NOT NULL
GROUP BY course_id, task_id
ORDER BY course_id, task_id;

-- Confirmar creación exitosa
DO $$
BEGIN
    RAISE NOTICE '✅ Schema de automatizacion Académica creado correctamente.';
    RAISE NOTICE '   Tablas: attendance, task_submissions, feedback, reports, error_logs, notifications_log';
    RAISE NOTICE '   Vistas: vw_attendance_summary, vw_task_summary, vw_grade_summary';
END $$;
