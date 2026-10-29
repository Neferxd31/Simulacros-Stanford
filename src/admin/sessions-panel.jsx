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

  // Estudiantes que ya tienen asignado este simulacro en alguna sesión
  const assignedTo = (examId) =>
    new Set(
      sessions
        .filter((session) => session.exams.id === examId)
        .flatMap((session) => session.session_students.map((assignment) => assignment.student_id)),
    )
  const alreadyAssigned = assignedTo(form.examId)

  const selectExam = (examId) => {
    const assigned = assignedTo(examId)
    setForm({ ...form, examId, studentIds: form.studentIds.filter((id) => !assigned.has(id)) })
  }

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
      // No dejar una sesión vacía si la base rechaza una asignación repetida
      await supabase.from('sessions').delete().eq('id', data.id)
      setError(studentsError.message)
      return
    }
    setForm(EMPTY_FORM)
    load()
  }

  // Borrar la asignación borra en cascada el intento y las respuestas
  const removeStudent = async (session, assignment) => {
    const warning = assignment.attempts ? ' Se borrarán su intento y sus respuestas.' : ''
    if (!window.confirm(`¿Quitar a ${studentLabel(assignment.profiles)} de esta sesión?${warning}`)) return
    setError('')
    const { error: deleteError } = await supabase
      .from('session_students')
      .delete()
      .eq('session_id', session.id)
      .eq('student_id', assignment.student_id)
    if (deleteError) {
      setError(deleteError.message)
      return
    }
    load()
  }

  const deleteSession = async (session) => {
    const started = session.session_students.some((assignment) => assignment.attempts)
    const warning = started ? ' Se borrarán los intentos y respuestas de sus estudiantes.' : ''
    if (!window.confirm(`¿Eliminar la sesión del ${formatBogota(session.starts_at)}?${warning}`)) return
    setError('')
    const { error: deleteError } = await supabase.from('sessions').delete().eq('id', session.id)
    if (deleteError) {
      setError(deleteError.message)
      return
    }
    load()
  }

  if (sheet) return <AnswerSheet {...sheet} onBack={() => setSheet(null)} />

  return (
    <section className="sessions-layout">
      <div>
        <h2>Asignar simulacro</h2>
        <form className="session-form card" onSubmit={createSession}>
          <label>
            Simulacro
            <select value={form.examId} onChange={(event) => selectExam(event.target.value)} required>
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
                  disabled={alreadyAssigned.has(student.id)}
                  onChange={() => toggleStudent(student.id)}
                />
                <span>
                  {studentLabel(student)}
                  {alreadyAssigned.has(student.id) && <small className="assigned-note">Ya tiene este simulacro asignado</small>}
                </span>
              </label>
            ))}
          </fieldset>
          <button type="submit" className="primary" disabled={form.studentIds.length === 0}>
            Asignar
          </button>
        </form>
        {error && <p role="alert">{error}</p>}
      </div>

      <div>
        <div className="section-title">
          <h2>Sesiones</h2>
          <button onClick={load}>Actualizar</button>
        </div>
        {sessions.length === 0 && <p>Todavía no hay sesiones.</p>}
        {sessions.map((session) => (
          <article key={session.id} className="session">
            <div className="session-header">
              <h3>
                {session.exams.title} · {formatBogota(session.starts_at)}
              </h3>
              <button className="link-danger" onClick={() => deleteSession(session)}>
                Eliminar sesión
              </button>
            </div>
            {session.session_students.length === 0 && <p>Sin estudiantes asignadas.</p>}
            <ul className="list">
              {session.session_students.map((assignment) => {
                // One-to-one (unique session_id, student_id): PostgREST returns an object or null
                const attempt = assignment.attempts
                return (
                  <li key={assignment.student_id}>
                    <span className="list-label">
                      {studentLabel(assignment.profiles)}
                      <span className={`badge badge-${attempt?.attempt_status ?? 'none'}`}>
                        {attempt ? STATUS_LABELS[attempt.attempt_status] : 'Sin iniciar'}
                      </span>
                    </span>
                    <span className="row-actions">
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
                      <button className="link-danger" onClick={() => removeStudent(session, assignment)}>
                        Quitar
                      </button>
                    </span>
                  </li>
                )
              })}
            </ul>
          </article>
        ))}
      </div>
    </section>
  )
}
