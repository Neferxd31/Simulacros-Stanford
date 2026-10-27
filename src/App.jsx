import { useEffect, useState } from 'react'
import { supabase } from './lib/supabase-client.js'

function App() {
  const [session, setSession] = useState(null)
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState('')

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => setSession(data.session))
    const { data } = supabase.auth.onAuthStateChange((_event, newSession) => setSession(newSession))
    return () => data.subscription.unsubscribe()
  }, [])

  const handleSubmit = async (event) => {
    event.preventDefault()
    setError('')
    const { error: signInError } = await supabase.auth.signInWithPassword({ email, password })
    if (signInError) setError(signInError.message)
  }

  if (session) {
    return (
      <main>
        <p>Sesión iniciada como {session.user.email}</p>
        <button onClick={() => supabase.auth.signOut()}>Cerrar sesión</button>
      </main>
    )
  }

  return (
    <main>
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

export default App
