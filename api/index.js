const express = require('express');
const { Pool }  = require('pg');
const multer    = require('multer');
const path      = require('path');
const fs        = require('fs');
const cors      = require('cors');

const app  = express();
const PORT = 3001;

app.use(cors());
app.use(express.json({ limit: '5mb' }));

// ── PostgreSQL pool ──────────────────────────────────────────────────────────
const pool = new Pool({
  host:     process.env.POSTGRES_HOST     || 'postgres',
  port:     parseInt(process.env.POSTGRES_PORT || '5432'),
  database: process.env.POSTGRES_DB       || 'academic_db',
  user:     process.env.POSTGRES_USER     || 'academic_user',
  password: process.env.POSTGRES_PASSWORD || 'postgres',
});

pool.on('error', (err) => console.error('PG pool error:', err.message));

// ── File upload (multer) ─────────────────────────────────────────────────────
const UPLOAD_DIR = '/data/uploads';
if (!fs.existsSync(UPLOAD_DIR)) fs.mkdirSync(UPLOAD_DIR, { recursive: true });

const storage = multer.diskStorage({
  destination: (_req, _file, cb) => cb(null, UPLOAD_DIR),
  filename:    (_req,  file, cb) => {
    const safe = file.originalname.replace(/[^a-zA-Z0-9._-]/g, '_');
    cb(null, `${Date.now()}_${safe}`);
  },
});
const upload = multer({ storage, limits: { fileSize: 20 * 1024 * 1024 } });

// ── Health ───────────────────────────────────────────────────────────────────
app.get('/health', (_req, res) => res.json({ ok: true }));

// ── Dashboard stats ──────────────────────────────────────────────────────────
app.get('/stats', async (_req, res) => {
  try {
    const [att, subs, fb, errs, rpts, notifs] = await Promise.all([
      pool.query(`
        SELECT COUNT(*)                                                   AS total,
               SUM(CASE WHEN status='present' THEN 1 ELSE 0 END)         AS present,
               SUM(CASE WHEN status='absent'  THEN 1 ELSE 0 END)         AS absent,
               SUM(CASE WHEN status='late'    THEN 1 ELSE 0 END)         AS late,
               ROUND(SUM(CASE WHEN status='present' THEN 1 ELSE 0 END)*100.0
                     / NULLIF(COUNT(*),0), 1)                            AS rate
        FROM attendance`),
      pool.query(`
        SELECT COUNT(*)                                                   AS total,
               SUM(CASE WHEN status='on_time'  THEN 1 ELSE 0 END)        AS on_time,
               SUM(CASE WHEN is_late           THEN 1 ELSE 0 END)        AS late,
               SUM(CASE WHEN status='missing'  THEN 1 ELSE 0 END)        AS missing
        FROM task_submissions`),
      pool.query(`
        SELECT COUNT(*)                                                   AS total,
               ROUND(AVG(grade),1)                                        AS avg_grade,
               SUM(CASE WHEN grade>=60 THEN 1 ELSE 0 END)                AS passing,
               SUM(CASE WHEN grade<60  THEN 1 ELSE 0 END)                AS failing
        FROM feedback WHERE grade IS NOT NULL`),
      pool.query(`SELECT COUNT(*) AS total FROM error_logs`),
      pool.query(`SELECT COUNT(*) AS total FROM reports`),
      pool.query(`SELECT COUNT(*) AS total FROM notifications_log`),
    ]);

    res.json({
      attendance: {
        total:   +att.rows[0].total,
        present: +(att.rows[0].present  || 0),
        absent:  +(att.rows[0].absent   || 0),
        late:    +(att.rows[0].late     || 0),
        rate:    parseFloat(att.rows[0].rate || 0),
      },
      submissions: {
        total:   +subs.rows[0].total,
        on_time: +(subs.rows[0].on_time || 0),
        late:    +(subs.rows[0].late    || 0),
        missing: +(subs.rows[0].missing || 0),
      },
      feedback: {
        total:     +fb.rows[0].total,
        avg_grade: parseFloat(fb.rows[0].avg_grade || 0),
        passing:   +(fb.rows[0].passing || 0),
        failing:   +(fb.rows[0].failing || 0),
      },
      system: {
        errors:        +errs.rows[0].total,
        reports:       +rpts.rows[0].total,
        notifications: +notifs.rows[0].total,
      },
    });
  } catch (e) {
    console.error('/stats error:', e.message);
    res.status(500).json({ error: e.message });
  }
});

// ── Recent submissions (for dashboard overview) ──────────────────────────────
app.get('/submissions/recent', async (_req, res) => {
  try {
    const r = await pool.query(`
      SELECT student_id, student_name, task_id, task_name, status, is_late,
             TO_CHAR(created_at,'YYYY-MM-DD HH24:MI') AS fecha
      FROM task_submissions
      ORDER BY created_at DESC LIMIT 10`);
    res.json(r.rows);
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// ── All submissions (profesor) / by student ──────────────────────────────────
app.get('/submissions', async (req, res) => {
  const { student_id } = req.query;
  try {
    let q = `
      SELECT id, student_id, student_name, task_id, task_name,
             file_name, file_extension, status, is_late,
             TO_CHAR(created_at,'YYYY-MM-DD HH24:MI') AS fecha
      FROM task_submissions`;
    const params = [];
    if (student_id) { q += ' WHERE student_id = $1'; params.push(student_id); }
    q += ' ORDER BY created_at DESC';
    const r = await pool.query(q, params);
    res.json(r.rows);
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// ── Create task submission ────────────────────────────────────────────────────
app.post('/submissions', async (req, res) => {
  const { student_id, student_name, task_id, task_name,
          deadline, file_name, file_extension, file_path: fp } = req.body;

  if (!student_id || !task_id)
    return res.status(400).json({ error: 'student_id y task_id son requeridos' });

  const now = new Date();
  const dl  = deadline ? new Date(deadline) : null;
  const is_late = dl ? now > dl : false;
  const status  = is_late ? 'late' : 'on_time';

  try {
    const r = await pool.query(
      `INSERT INTO task_submissions
         (student_id, student_name, task_id, task_name,
          submission_date, deadline, status, file_name, file_extension, is_late)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10) RETURNING *`,
      [student_id, student_name||'', task_id, task_name||'',
       now, dl, status, file_name||'', file_extension||'', is_late]);

    res.json({ success: true, status, is_late, data: r.rows[0] });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// ── File upload ───────────────────────────────────────────────────────────────
app.post('/upload', upload.single('file'), (req, res) => {
  if (!req.file) return res.status(400).json({ error: 'No se recibió archivo' });
  res.json({
    success:      true,
    filename:     req.file.filename,
    originalname: req.file.originalname,
    size:         req.file.size,
    mimetype:     req.file.mimetype,
  });
});

// ── Attendance bulk (CSV upload parsed by frontend) ──────────────────────────
app.post('/attendance/csv', async (req, res) => {
  const { rows } = req.body;
  if (!Array.isArray(rows) || !rows.length)
    return res.status(400).json({ error: 'No se encontraron filas en el CSV' });

  const VALID_STATUS = ['present','absent','late','excused'];
  let inserted = 0, skipped = 0;
  const errors = [];
  const client = await pool.connect();

  try {
    await client.query('BEGIN');
    for (const row of rows) {
      const sid    = (row.student_id   || '').trim();
      const sname  = (row.student_name || '').trim();
      const cid    = (row.course_id    || '').trim();
      const date   = (row.date         || '').trim();
      const status = (row.status       || '').trim().toLowerCase();

      if (!sid || !cid || !date || !status) { skipped++; continue; }
      if (!VALID_STATUS.includes(status)) {
        errors.push(`Fila ${sid}: estado inválido "${status}"`);
        skipped++; continue;
      }

      try {
        await client.query(
          `INSERT INTO attendance (student_id, student_name, course_id, date, status)
           VALUES ($1,$2,$3,$4,$5)
           ON CONFLICT (student_id, course_id, date)
           DO UPDATE SET status=$5, student_name=$2`,
          [sid, sname, cid, date, status]);
        inserted++;
      } catch (rowErr) {
        errors.push(`Fila ${sid}: ${rowErr.message}`);
        skipped++;
      }
    }
    await client.query('COMMIT');
    res.json({ success: true, inserted, skipped, errors });
  } catch (e) {
    await client.query('ROLLBACK');
    res.status(500).json({ error: e.message });
  } finally {
    client.release();
  }
});

// ── Attendance list (profesor) ───────────────────────────────────────────────
app.get('/attendance', async (_req, res) => {
  try {
    const r = await pool.query(`
      SELECT student_id, student_name, course_id, date::text, status,
             TO_CHAR(processed_at,'YYYY-MM-DD HH24:MI') AS processed_at
      FROM attendance
      ORDER BY date DESC, course_id
      LIMIT 300`);
    res.json(r.rows);
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// ── Feedback / grades (professor creates, student reads by ID) ───────────────
app.get('/feedback', async (req, res) => {
  const { student_id } = req.query;
  try {
    let q = `
      SELECT id, student_id, student_name, course_id, task_id,
             grade, feedback_text, feedback_type,
             TO_CHAR(created_at,'YYYY-MM-DD HH24:MI') AS fecha
      FROM feedback`;
    const params = [];
    if (student_id) { q += ' WHERE student_id = $1'; params.push(student_id); }
    q += ' ORDER BY created_at DESC';
    const r = await pool.query(q, params);
    res.json(r.rows);
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

app.post('/feedback', async (req, res) => {
  const { student_id, student_name, course_id, task_id,
          grade, feedback_text, feedback_type } = req.body;

  if (!student_id || !task_id)
    return res.status(400).json({ error: 'student_id y task_id son requeridos' });

  const g  = parseFloat(grade) || 0;
  const ft = feedback_type || (g >= 80 ? 'positive' : g >= 60 ? 'neutral' : 'negative');

  try {
    const r = await pool.query(
      `INSERT INTO feedback
         (student_id, student_name, course_id, task_id, grade, feedback_text, feedback_type)
       VALUES ($1,$2,$3,$4,$5,$6,$7) RETURNING *`,
      [student_id, student_name||'', course_id||'', task_id,
       g, feedback_text||'', ft]);
    res.json({ success: true, data: r.rows[0] });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// ── Error logs ───────────────────────────────────────────────────────────────
app.get('/errors', async (_req, res) => {
  try {
    const r = await pool.query(`
      SELECT workflow_name, node_name, error_message,
             TO_CHAR(created_at,'YYYY-MM-DD HH24:MI') AS created_at
      FROM error_logs
      ORDER BY created_at DESC LIMIT 50`);
    res.json(r.rows);
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// ── Reports list ─────────────────────────────────────────────────────────────
app.get('/reports', async (_req, res) => {
  try {
    const r = await pool.query(`
      SELECT report_type, course_id, file_path, records_count, status,
             TO_CHAR(generated_at,'YYYY-MM-DD HH24:MI') AS generated_at
      FROM reports
      ORDER BY generated_at DESC LIMIT 50`);
    res.json(r.rows);
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

// ── Start ─────────────────────────────────────────────────────────────────────
app.listen(PORT, () => console.log(`Academic API running on port ${PORT}`));
