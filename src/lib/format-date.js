const bogotaFormat = new Intl.DateTimeFormat('es-CO', {
  timeZone: 'America/Bogota',
  dateStyle: 'medium',
  timeStyle: 'short',
})

export const formatBogota = (isoDate) => bogotaFormat.format(new Date(isoDate))

// Valor de <input type="datetime-local"> en hora de Bogotá (UTC-5, sin horario de verano) -> ISO en UTC
export const bogotaInputToIso = (value) => new Date(`${value}:00-05:00`).toISOString()

export const formatSeconds = (totalSeconds) => {
  const seconds = Math.max(0, Math.ceil(totalSeconds))
  return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, '0')}`
}
