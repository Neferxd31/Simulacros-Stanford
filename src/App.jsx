import { useEffect, useState } from 'react'
import { supabase } from './lib/supabase-client.js'
import AdminHome from './admin/admin-home.jsx'
import StudentHome from './student/student-home.jsx'

function App() {
  const [session, setSession] = useState(null)
  const [profile, setProfile] = useState(null)
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
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
        <h1>Simulacros TOEIC</h1>
        <form onSubmit={handleSubmit}>
          <input type="email" placeholder="Correo" value={email} onChange={(event) => setEmail(event.target.value)} required />
          <input type="password" placeholder="Contraseña" value={password} onChange={(event) => setPassword(event.target.value)} required />
          <button type="submit">Iniciar sesión</button>
        </form>
        {error && <p role="alert">{error}</p>}
      </main>
    )
  }

  return (
    <main>
      <header className="app-header no-print">
        <strong>Simulacros TOEIC</strong>
        <span>{session.user.email}</span>
        <button onClick={() => supabase.auth.signOut()}>Cerrar sesión</button>
      </header>
      {role === 'admin' && <AdminHome />}
      {role === 'student' && <StudentHome />}
      {!role && <p>Cargando…</p>}
    </main>
  )
}

export default App
