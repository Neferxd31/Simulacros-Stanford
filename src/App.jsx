import { useEffect, useState } from 'react'
import { supabase } from './lib/supabase-client.js'
import AccountSettings from './account-settings.jsx'
import AdminHome from './admin/admin-home.jsx'
import StudentHome from './student/student-home.jsx'

const ROLE_LABELS = { admin: 'Docente', student: 'Estudiante' }

function App() {
  const [session, setSession] = useState(null)
  const [profile, setProfile] = useState(null)
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [accountOpen, setAccountOpen] = useState(false)
  const [error, setError] = useState('')

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => setSession(data.session))
    const { data } = supabase.auth.onAuthStateChange((_event, newSession) => setSession(newSession))
    return () => data.subscription.unsubscribe()
  }, [])

  const userId = session?.user.id
  useEffect(() => {
    if (!userId) return
    supabase.from('profiles').select('id, role').eq('id', userId).single().then(({ data }) => setProfile(data))
  }, [userId])
  // Ignore a profile left over from a previous user until the new one loads
  const role = profile && profile.id === userId ? profile.role : null

  const handleSubmit = async (event) => {
    event.preventDefault()
    setError('')
    const { error: signInError } = await supabase.auth.signInWithPassword({ email, password })
    if (signInError) setError(signInError.message)
  }

  if (!session) {
    return (
      <main className="login">
        <section className="login-brand">
          <img className="logo" src="/logo.webp" alt="Stanford English Academy" width="140" height="140" />
          <h1>Stanford English Academy</h1>
          <p>Plataforma de simulacros TOEIC</p>
        </section>
        <section className="login-panel">
          <div className="login-card">
            <h2>Iniciar sesión</h2>
            <p>Ingresa con el correo y la contraseña que te entregó la academia.</p>
            <form onSubmit={handleSubmit}>
              <label>
                Correo
                <input type="email" value={email} onChange={(event) => setEmail(event.target.value)} required />
              </label>
              <label>
                Contraseña
                <input type="password" value={password} onChange={(event) => setPassword(event.target.value)} required />
              </label>
              <button type="submit" className="primary">
                Ingresar
              </button>
            </form>
            {error && <p role="alert">{error}</p>}
          </div>
        </section>
      </main>
    )
  }

  return (
    <div className="app">
      <header className="app-header no-print">
        <div className="app-header-inner">
          <div className="brand">
            <img className="logo" src="/logo.webp" alt="" width="48" height="48" />
            <div>
              <strong>Stanford English Academy</strong>
              <span>Simulacros TOEIC</span>
            </div>
          </div>
          <div className="user">
            <div className="user-info">
              <span>{session.user.email}</span>
              {role && <small>{ROLE_LABELS[role]}</small>}
            </div>
            <button onClick={() => setAccountOpen(true)}>Mi cuenta</button>
            <button onClick={() => supabase.auth.signOut()}>Cerrar sesión</button>
          </div>
        </div>
      </header>
      <main className="content">
        {role === 'admin' && <AdminHome />}
        {role === 'student' && <StudentHome />}
        {!role && <p>Cargando…</p>}
      </main>
      <footer className="app-footer no-print">Stanford English Academy · Simulacros TOEIC</footer>
      {accountOpen && <AccountSettings email={session.user.email} onClose={() => setAccountOpen(false)} />}
    </div>
  )
}

export default App
