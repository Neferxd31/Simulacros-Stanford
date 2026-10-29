import { useEffect, useRef, useState } from 'react'
import { supabase } from './lib/supabase-client.js'

export default function AccountSettings({ email, onClose }) {
  const dialogRef = useRef(null)
  const [newEmail, setNewEmail] = useState(email)
  const [password, setPassword] = useState('')
  const [confirmation, setConfirmation] = useState('')
  const [message, setMessage] = useState('')
  const [error, setError] = useState('')

  useEffect(() => {
    dialogRef.current.showModal()
  }, [])

  const updateEmail = async (event) => {
    event.preventDefault()
    setMessage('')
    setError('')
    // RPC instead of auth.updateUser: Supabase would require a confirmation email that never arrives
    const { error: updateError } = await supabase.rpc('change_my_email', { p_email: newEmail })
    if (updateError) {
      setError(updateError.message)
      return
    }
    // The session token still carries the old email until it is refreshed
    await supabase.auth.refreshSession()
    setMessage('Correo actualizado. Úsalo la próxima vez que inicies sesión.')
  }

  const updatePassword = async (event) => {
    event.preventDefault()
    setMessage('')
    setError('')
    if (password !== confirmation) {
      setError('Las contraseñas no coinciden.')
      return
    }
    const { error: updateError } = await supabase.auth.updateUser({ password })
    if (updateError) {
      setError(updateError.message)
      return
    }
    setPassword('')
    setConfirmation('')
    setMessage('Contraseña actualizada.')
  }

  return (
    <dialog ref={dialogRef} className="account-dialog" onClose={onClose}>
      <div className="dialog-header">
        <h2>Mi cuenta</h2>
        <button type="button" className="close-button" aria-label="Cerrar" onClick={() => dialogRef.current.close()}>
          ×
        </button>
      </div>
      <form onSubmit={updateEmail}>
        <h3>Correo de inicio de sesión</h3>
        <label>
          Correo
          <input type="email" value={newEmail} onChange={(event) => setNewEmail(event.target.value)} required />
        </label>
        <button type="submit" className="primary" disabled={newEmail === email}>
          Guardar correo
        </button>
      </form>
      <form onSubmit={updatePassword}>
        <h3>Contraseña</h3>
        <label>
          Nueva contraseña
          <input
            type="password"
            autoComplete="new-password"
            minLength={8}
            value={password}
            onChange={(event) => setPassword(event.target.value)}
            required
          />
        </label>
        <label>
          Repite la contraseña
          <input
            type="password"
            autoComplete="new-password"
            minLength={8}
            value={confirmation}
            onChange={(event) => setConfirmation(event.target.value)}
            required
          />
        </label>
        <button type="submit" className="primary">
          Guardar contraseña
        </button>
      </form>
      {message && (
        <p role="status" className="notice">
          {message}
        </p>
      )}
      {error && <p role="alert">{error}</p>}
    </dialog>
  )
}
