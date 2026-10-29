import { useCallback, useEffect, useState } from 'react'
import { supabase } from '../lib/supabase-client.js'

const EMPTY_FORM = { fullName: '', email: '', password: '' }

export default function StudentsPanel() {
  const [students, setStudents] = useState([])
  const [form, setForm] = useState(EMPTY_FORM)
  const [message, setMessage] = useState('')
  const [error, setError] = useState('')

  const load = useCallback(
    () =>
      supabase
        .from('profiles')
        .select('id, full_name, email')
        .eq('role', 'student')
        .order('full_name')
        .then(({ data, error: loadError }) => {
          if (loadError) {
            setError(loadError.message)
            return
          }
          setStudents(data)
        }),
    [],
  )

  useEffect(() => {
    load()
  }, [load])

  const createStudent = async (event) => {
    event.preventDefault()
    setMessage('')
    setError('')
    const { error: createError } = await supabase.rpc('create_student', {
      p_email: form.email,
      p_password: form.password,
      p_full_name: form.fullName,
    })
    if (createError) {
      setError(createError.message)
      return
    }
    setMessage(`Cuenta creada. ${form.fullName} ya puede entrar con su correo y contraseña.`)
    setForm(EMPTY_FORM)
    load()
  }

  const deleteStudent = async (student) => {
    const name = student.full_name || student.email
    if (!window.confirm(`¿Eliminar la cuenta de ${name}? Se borrarán sus asignaciones, intentos y respuestas. No se puede deshacer.`)) return
    setMessage('')
    setError('')
    const { error: deleteError } = await supabase.rpc('delete_student', { p_student_id: student.id })
    if (deleteError) {
      setError(deleteError.message)
      return
    }
    setMessage(`Cuenta de ${name} eliminada.`)
    load()
  }

  return (
    <section className="sessions-layout">
      <div>
        <h2>Nueva estudiante</h2>
        <form className="card" onSubmit={createStudent}>
          <label>
            Nombre completo
            <input value={form.fullName} onChange={(event) => setForm({ ...form, fullName: event.target.value })} required />
          </label>
          <label>
            Correo
            <input
              type="email"
              value={form.email}
              onChange={(event) => setForm({ ...form, email: event.target.value })}
              required
            />
          </label>
          <label>
            Contraseña
            <input
              type="text"
              autoComplete="off"
              minLength={8}
              value={form.password}
              onChange={(event) => setForm({ ...form, password: event.target.value })}
              required
            />
          </label>
          <button type="submit" className="primary">
            Crear estudiante
          </button>
        </form>
        {message && (
          <p role="status" className="notice">
            {message}
          </p>
        )}
        {error && <p role="alert">{error}</p>}
      </div>

      <div>
        <h2>Estudiantes</h2>
        {students.length === 0 && <p>No hay estudiantes registradas.</p>}
        <ul className="list">
          {students.map((student) => (
            <li key={student.id}>
              <span className="list-title">
                <strong>{student.full_name || student.email}</strong>
                <small>{student.email}</small>
              </span>
              <button className="link-danger" onClick={() => deleteStudent(student)}>
                Eliminar
              </button>
            </li>
          ))}
        </ul>
      </div>
    </section>
  )
}
