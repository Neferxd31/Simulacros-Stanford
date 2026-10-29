import { useCallback, useEffect, useRef, useState } from 'react'
import { supabase } from '../lib/supabase-client.js'
import { formatSeconds } from '../lib/format-date.js'

const OPTIONS = ['A', 'B', 'C', 'D']
const AUDIO_CACHE = 'exam-audio'

// Cached by the stable storage path, not by the signed URL (it changes on every request),
// so a reload does not download the audio again
const loadAudio = async (audioPath) => {
  const cache = await caches.open(AUDIO_CACHE)
  const key = new URL(`/audio-cache/${audioPath}`, window.location.origin)
  const cached = await cache.match(key)
  if (cached) return URL.createObjectURL(await cached.blob())

  const { data, error } = await supabase.storage.from('exams').createSignedUrl(audioPath, 60)
  if (error) throw error
  const response = await fetch(data.signedUrl)
  if (!response.ok) throw new Error('No se pudo descargar el audio')
  const blob = await response.blob()
  await cache.put(key, new Response(blob))
  return URL.createObjectURL(blob)
}

const expectedAudioSecond = (current) =>
  (Date.now() + current.clockOffset - new Date(current.current_part_started_at).getTime()) / 1000

// Lleva el audio al segundo que dicta el servidor: no se puede pausar ni retroceder
const resumeAudio = (audio, current) => {
  const expected = expectedAudioSecond(current)
  if (audio.readyState === 0 || audio.ended || expected >= audio.duration) return
  audio.currentTime = expected
  // Without a prior click the browser rejects play(); the next click or key press retries it
  audio.play().catch(() => {})
}

// Retoma según la hora del servidor: tras una recarga no se reinicia el audio
const playFromServerTime = async (audio, current) => {
  audio.src = await loadAudio(current.audio_path)
  await new Promise((resolve) => audio.addEventListener('loadedmetadata', resolve, { once: true }))
  resumeAudio(audio, current)
}

const questionRange = (first, last) => Array.from({ length: last - first + 1 }, (_, index) => first + index)

export default function ExamView({ attemptId, onExit }) {
  const [state, setState] = useState(null)
  const [now, setNow] = useState(() => Date.now())
  const [answers, setAnswers] = useState({})
  const [pageUrls, setPageUrls] = useState({})
  const [pageIndex, setPageIndex] = useState(0)
  const [audioPlaying, setAudioPlaying] = useState(false)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const audioRef = useRef(null)

  const loadState = useCallback(
    () =>
      supabase.rpc('attempt_state', { p_attempt_id: attemptId }).then(({ data, error: stateError }) => {
        if (stateError) {
          setError(stateError.message)
          return null
        }
        // Server clock minus local clock: every countdown uses server time
        const clockOffset = data.server_now ? new Date(data.server_now).getTime() - Date.now() : 0
        const next = { ...data, clockOffset }
        setState(next)
        setAnswers(data.answers ?? {})
        setPageIndex(0)
        return next
      }),
    [attemptId],
  )

  useEffect(() => {
    loadState()
  }, [loadState])

  useEffect(() => {
    const timer = setInterval(() => setNow(Date.now()), 1000)
    return () => clearInterval(timer)
  }, [])

  useEffect(() => {
    if (!state?.pages?.length) return
    const paths = state.pages.map((page) => page.image_path)
    supabase.storage.from('exams').createSignedUrls(paths, 600).then(({ data, error: signError }) => {
      if (signError) {
        setError(signError.message)
        return
      }
      setPageUrls(Object.fromEntries(data.map((item) => [item.path, item.signedUrl])))
    })
  }, [state])

  const serverNow = now + (state?.clockOffset ?? 0)
  const status = state?.status
  const currentPart = state?.parts?.find((part) => part.part === state.current_part)
  const partEndsAt = currentPart
    ? new Date(state.current_part_started_at).getTime() + currentPart.audio_duration_s * 1000
    : 0
  const partPlaying = status === 'listening' && serverNow < partEndsAt
  const nextPart = state?.parts?.find((part) => part.section === 'listening' && part.part > (state.current_part ?? 0))
  const readingDue = status === 'listening' && Boolean(state.reading_started_at) && serverNow >= new Date(state.reading_started_at).getTime()
  const readingEndsAt = state?.reading_ends_at ? new Date(state.reading_ends_at).getTime() : 0
  const readingExpired = status === 'reading' && serverNow >= readingEndsAt

  // Al terminar el último audio el servidor ya cuenta Reading
  useEffect(() => {
    if (readingDue) loadState()
  }, [readingDue, loadState])

  // Al vencer el tiempo se envía lo marcado (el servidor ya lo considera enviado de todos modos)
  useEffect(() => {
    if (!readingExpired) return
    supabase.rpc('submit_attempt', { p_attempt_id: attemptId }).then(loadState)
  }, [readingExpired, attemptId, loadState])

  useEffect(() => {
    if (status === 'submitted') caches.delete(AUDIO_CACHE)
  }, [status])

  // Al entrar (o recargar) en Listening el audio arranca solo, en el segundo que corresponde
  useEffect(() => {
    if (state?.status !== 'listening') return
    const part = state.parts.find((item) => item.part === state.current_part)
    if (expectedAudioSecond(state) >= part.audio_duration_s) return
    playFromServerTime(audioRef.current, state).catch((audioError) => setError(audioError.message))
  }, [state])

  // Si el navegador bloqueó el sonido tras recargar, cualquier clic o tecla lo retoma
  useEffect(() => {
    if (state?.status !== 'listening') return
    const resume = () => {
      if (audioRef.current.paused) resumeAudio(audioRef.current, state)
    }
    document.addEventListener('pointerdown', resume)
    document.addEventListener('keydown', resume)
    return () => {
      document.removeEventListener('pointerdown', resume)
      document.removeEventListener('keydown', resume)
    }
  }, [state])

  // Durante la prueba, recargar o cerrar la pestaña pide confirmación
  useEffect(() => {
    if (status !== 'listening' && status !== 'reading') return
    const warn = (event) => event.preventDefault()
    window.addEventListener('beforeunload', warn)
    return () => window.removeEventListener('beforeunload', warn)
  }, [status])

  // Sin pausa: si algo detiene el audio antes de tiempo, vuelve al segundo que corresponde
  const handlePause = () => {
    setAudioPlaying(false)
    resumeAudio(audioRef.current, state)
  }

  const run = async (action) => {
    setBusy(true)
    setError('')
    try {
      await action()
    } catch (actionError) {
      setError(actionError.message)
    }
    setBusy(false)
  }

  const startNextPart = () =>
    run(async () => {
      const { error: startError } = await supabase.rpc('start_next_part', { p_attempt_id: attemptId })
      if (startError) throw startError
      await loadState()
    })

  const submit = () => {
    if (!window.confirm('¿Enviar la prueba? Después no podrás ver ni cambiar tus respuestas.')) return
    run(async () => {
      const { error: submitError } = await supabase.rpc('submit_attempt', { p_attempt_id: attemptId })
      if (submitError) throw submitError
      await loadState()
    })
  }

  const selectOption = async (question, option) => {
    const previous = answers[question]
    setAnswers((current) => ({ ...current, [question]: option }))
    const { error: saveError } = await supabase.rpc('save_answer', {
      p_attempt_id: attemptId,
      p_question: question,
      p_option: option,
    })
    if (!saveError) return
    setAnswers((current) => ({ ...current, [question]: previous }))
    setError(saveError.message)
  }

  if (!state) return <p>{error || 'Cargando…'}</p>

  if (status === 'submitted') {
    return (
      <section>
        <h2>Prueba enviada</h2>
        <p>Tus respuestas quedaron registradas.</p>
        <button onClick={onExit}>Volver</button>
      </section>
    )
  }

  const page = state.pages[pageIndex]
  const pagePart = state.parts.find((part) => part.part === page?.part)
  const questions = page?.first_q ? questionRange(page.first_q, page.last_q) : []
  const canStartNext = nextPart && (status === 'pending' || (status === 'listening' && !partPlaying))

  return (
    <section>
      <audio ref={audioRef} onPlaying={() => setAudioPlaying(true)} onPause={handlePause} />
      <div className="exam-bar">
        {status === 'pending' && <strong>Listening</strong>}
        {status === 'listening' && (
          <strong>
            Listening · Parte {state.current_part} ·{' '}
            <span className="timer">
              {partPlaying ? `audio ${formatSeconds((partEndsAt - serverNow) / 1000)}` : 'audio terminado'}
            </span>
          </strong>
        )}
        {status === 'reading' && (
          <strong>
            Reading · <span className="timer">quedan {formatSeconds((readingEndsAt - serverNow) / 1000)}</span>
          </strong>
        )}
        {partPlaying && !audioPlaying && (
          <span className="audio-hint">Cargando audio… si no se escucha, haz clic en cualquier parte de la página.</span>
        )}
        {canStartNext && (
          <button className="primary" disabled={busy} onClick={startNextPart}>
            Comenzar parte {nextPart.part}
          </button>
        )}
        {status === 'reading' && (
          <button className="danger" disabled={busy} onClick={submit}>
            Enviar prueba
          </button>
        )}
      </div>
      {busy && <p>Procesando…</p>}
      {error && <p role="alert">{error}</p>}
      {status === 'pending' && <p>Cuando estés lista, comienza la parte 1. El audio no se puede pausar ni retroceder.</p>}
      {page && (
        <div className="exam">
          <div>
            <nav className="page-nav">
              {state.pages.map((item, index) => (
                <button key={item.page_order} aria-pressed={index === pageIndex} onClick={() => setPageIndex(index)}>
                  {index + 1}
                </button>
              ))}
            </nav>
            {pageUrls[page.image_path] && (
              <img className="page-image" src={pageUrls[page.image_path]} alt={`Página ${pageIndex + 1}`} />
            )}
          </div>
          <BubbleSheet questions={questions} choices={pagePart.choices_count} answers={answers} onSelect={selectOption} />
        </div>
      )}
    </section>
  )
}

function BubbleSheet({ questions, choices, answers, onSelect }) {
  if (questions.length === 0) {
    return (
      <aside className="bubbles">
        <p>Esta página no tiene preguntas.</p>
      </aside>
    )
  }
  return (
    <aside className="bubbles">
      {questions.map((question) => (
        <div key={question} className="bubble-row">
          <span>{question}.</span>
          {OPTIONS.slice(0, choices).map((option) => (
            <button
              key={option}
              className="bubble"
              aria-pressed={answers[question] === option}
              onClick={() => onSelect(question, option)}
            >
              {option}
            </button>
          ))}
        </div>
      ))}
    </aside>
  )
}
