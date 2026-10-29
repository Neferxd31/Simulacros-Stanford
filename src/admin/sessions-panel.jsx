import { useCallback, useEffect, useState } from 'react'
import { supabase } from '../lib/supabase-client.js'
import { bogotaInputToIso, formatBogota } from '../lib/format-date.js'
import AnswerSheet from './answer-sheet.jsx'

const STATUS_LABELS = { pending: 'Pendiente', listening: 'Listening', reading: 'Reading', submitted: 'Enviada' }
const EMPTY_FORM = { examId: '', startsAt: '', studentIds: [] }

const studentLabel = (profile) => profile.full_name || profile.email

export default function SessionsPanel() {
  const [sessions, setSessions] = useState([])
  const [exams, setExams] = useState([])
  const [students, setStudents] = useState([])
  const [form, setForm] = useState(EMPTY_FORM)
  const [sheet, setSheet] = useState(null)
  const [error, setError] = useState('')

  const load = useCallback(
    () =>
      Promise.all([
        supabase
          .from('sessions')
          .select('id, starts_at, exams(id, title), session_students(student_id, profiles(full_name, email), attempts(id, attempt_status))')
          .order('starts_at', { ascending: false }),
        supabase.from('exams').select('id, title').eq('status', 'approved').order('id'),
        supabase.from('profiles').select('id, full_name, email').eq('role', 'student').order('email'),
      ]).then((results) => {
        const failed = results.find((result) => result.error)
        if (failed) {
          setError(failed.error.message)
          return
        }
        const [sessionsResult, examsResult, studentsResult] = results
        setSessions(sessionsResult.data)
        setExams(examsResult.data)
        setStudents(studentsResult.data)
      }),
    [],
  )

  useEffect(() => {
    load()
  }, [load])

  const toggleStudent = (studentId) => {
    setForm((current) => ({
      ...current,
      studentIds: current.studentIds.includes(studentId)
        ? current.studentIds.filter((id) => id !== studentId)
        : [...current.studentIds, studentId],
    }))
  }

  const createSession = async (event) => {
    event.preventDefault()
    setError('')
    const { data, error: sessionError } = await supabase
      .from('sessions')
      .insert({ exam_id: form.examId, starts_at: bogotaInputToIso(form.startsAt) })
      .select('id')
      .single()
    if (sessionError) {
      setError(sessionError.message)
      return
    }
    const rows = form.studentIds.map((studentId) => ({ session_id: data.id, student_id: studentId }))
    const { error: studentsError } = await supabase.from('session_students').insert(rows)
    if (studentsError) {
      setError(studentsError.message)
      return
    }
    setForm(EMPTY_FORM)
    load()
  }

  if (sheet) return <AnswerSheet {...sheet} onBack={() => setSheet(null)} />

  return (
    <section>
      <h2>Nueva sesión</h2>
      <form className="session-form" onSubmit={createSession}>
        <label>
          Simulacro
          <select value={form.examId} onChange={(event) => setForm({ ...form, examId: event.target.value })} required>
            <option value="">Elige un simulacro aprobado</option>
            {exams.map((exam) => (
              <option key={exam.id} value={exam.id}>
                {exam.title}
              </option>
            ))}
          </select>
        </label>
        <label>
          Inicio (hora de Bogotá)
          <input
            type="datetime-local"
            value={form.startsAt}
            onChange={(event) => setForm({ ...form, startsAt: event.target.value })}
            required
          />
        </label>
        <fieldset>
          <legend>Estudiantes</legend>
          {students.length === 0 && <p>No hay estudiantes registradas.</p>}
          {students.map((student) => (
            <label key={student.id} className="checkbox">
              <input
                type="checkbox"
                checked={form.studentIds.includes(student.id)}
                onChange={() => toggleStudent(student.id)}
              />
              {studentLabel(student)}
            </label>
          ))}
        </fieldset>
        <button type="submit" className="primary" disabled={form.studentIds.length === 0}>
          Crear sesión
        </button>
      </form>
      {error && <p role="alert">{error}</p>}

      <div className="section-title">
        <h2>Sesiones</h2>
        <button onClick={load}>Actualizar</button>
      </div>
      {sessions.length === 0 && <p>Todavía no hay sesiones.</p>}
      {sessions.map((session) => (
        <article key={session.id} className="session">
          <h3>
            {session.exams.title} · {formatBogota(session.starts_at)}
          </h3>
          <ul className="list">
            {session.session_students.map((assignment) => {
              // One-to-one (unique session_id, student_id): PostgREST returns an object or null
              const attempt = assignment.attempts
              return (
                <li key={assignment.student_id}>
                  <span>
                    {studentLabel(assignment.profiles)} · {attempt ? STATUS_LABELS[attempt.attempt_status] : 'Sin iniciar'}
                  </span>
                  {attempt && (
                    <button
                      onClick={() =>
                        setSheet({
                          attemptId: attempt.id,
                          studentName: studentLabel(assignment.profiles),
                          examId: session.exams.id,
                          examTitle: session.exams.title,
                          startsAt: session.starts_at,
                        })
                      }
                    >
                      Hoja de respuestas
                    </button>
                  )}
                </li>
              )
            })}
          </ul>
        </article>
      ))}
    </section>
  )
}
