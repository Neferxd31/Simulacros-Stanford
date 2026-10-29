import { useCallback, useEffect, useState } from 'react'
import { supabase } from '../lib/supabase-client.js'
import { formatBogota } from '../lib/format-date.js'
import ExamView from './exam-view.jsx'

export default function StudentHome() {
  const [assignments, setAssignments] = useState([])
  const [attemptId, setAttemptId] = useState(null)
  const [error, setError] = useState('')

  const load = useCallback(
    () =>
      supabase
        .from('session_students')
        .select('session_id, sessions(starts_at), attempts(id, attempt_status)')
        .then(({ data, error: loadError }) => {
          if (loadError) {
            setError(loadError.message)
            return
          }
          const loadedAt = new Date()
          const withAvailability = data.map((assignment) => ({
            ...assignment,
            available: new Date(assignment.sessions.starts_at) <= loadedAt,
          }))
          setAssignments(withAvailability.toSorted((a, b) => a.sessions.starts_at.localeCompare(b.sessions.starts_at)))
        }),
    [],
  )

  useEffect(() => {
    load()
    // Refresca para que "Iniciar" aparezca cuando llegue la hora
    const timer = setInterval(load, 30000)
    return () => clearInterval(timer)
  }, [load])

  const start = async (sessionId) => {
    setError('')
    const { data, error: startError } = await supabase.rpc('start_attempt', { p_session_id: sessionId })
    if (startError) {
      setError(startError.message)
      return
    }
    setAttemptId(data.id)
  }

  if (attemptId) {
    return (
      <ExamView
        attemptId={attemptId}
        onExit={() => {
          setAttemptId(null)
          load()
        }}
      />
    )
  }

  return (
    <section>
      <h2>Mis simulacros</h2>
      {error && <p role="alert">{error}</p>}
      {assignments.length === 0 && <p>No tienes simulacros asignados.</p>}
      <ul className="list">
        {assignments.map((assignment) => (
          <li key={assignment.session_id}>
            <span>Simulacro TOEIC · {formatBogota(assignment.sessions.starts_at)}</span>
            <AssignmentAction assignment={assignment} onStart={start} onContinue={setAttemptId} />
          </li>
        ))}
      </ul>
    </section>
  )
}

function AssignmentAction({ assignment, onStart, onContinue }) {
  // One-to-one (unique session_id, student_id): PostgREST returns an object or null
  const attempt = assignment.attempts
  if (attempt?.attempt_status === 'submitted') return <span>Prueba enviada</span>
  if (attempt) return <button onClick={() => onContinue(attempt.id)}>Continuar</button>
  if (!assignment.available) return <span>Aún no disponible</span>
  return <button onClick={() => onStart(assignment.session_id)}>Iniciar</button>
}
