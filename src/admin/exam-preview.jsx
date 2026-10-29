import { useEffect, useState } from 'react'
import { formatSeconds } from '../lib/format-date.js'
import BubbleSheet from '../student/bubble-sheet.jsx'

// Vista de la docente igual a la de la estudiante, pero sin esperar los audios y sin guardar nada
export default function ExamPreview({ exam, parts, pages, urls, onExit }) {
  const listeningParts = parts.filter((part) => part.section === 'listening')
  const [view, setView] = useState(listeningParts[0]?.part ?? 'reading')
  const [pageIndex, setPageIndex] = useState(0)
  const [answers, setAnswers] = useState({})
  const [audioLeft, setAudioLeft] = useState(null)
  const [readingStartedAt, setReadingStartedAt] = useState(null)
  const [now, setNow] = useState(() => Date.now())

  useEffect(() => {
    const timer = setInterval(() => setNow(Date.now()), 1000)
    return () => clearInterval(timer)
  }, [])

  const selectView = (nextView) => {
    setView(nextView)
    setPageIndex(0)
    setAudioLeft(null)
    // Como en la prueba real, el reloj de Reading arranca la primera vez que se entra
    if (nextView === 'reading' && !readingStartedAt) setReadingStartedAt(now)
  }

  const isReading = view === 'reading'
  const currentPart = parts.find((part) => part.part === view)
  // Como la estudiante: en Reading se ven juntas todas las partes de lectura
  const viewPages = pages.filter((page) =>
    isReading ? parts.some((part) => part.part === page.part && part.section === 'reading') : page.part === view,
  )
  const page = viewPages[pageIndex]
  const pagePart = parts.find((part) => part.part === page?.part)
  const readingLeft = readingStartedAt ? Math.max(0, exam.reading_minutes * 60 - (now - readingStartedAt) / 1000) : 0

  return (
    <section>
      <div className="preview-banner">
        <span>
          <strong>Vista previa como estudiante</strong> · {exam.title} · las respuestas no se guardan
        </span>
        <button onClick={onExit}>Salir</button>
      </div>
      <nav className="preview-parts">
        {listeningParts.map((part) => (
          <button key={part.part} aria-pressed={view === part.part} onClick={() => selectView(part.part)}>
            Parte {part.part}
          </button>
        ))}
        <button aria-pressed={isReading} onClick={() => selectView('reading')}>
          Reading
        </button>
      </nav>
      <div className="exam-bar">
        {isReading ? (
          <strong>
            Reading · <span className="timer">quedan {formatSeconds(readingLeft)}</span>
          </strong>
        ) : (
          <strong>
            Listening · Parte {view} ·{' '}
            <span className="timer">audio {formatSeconds(audioLeft ?? currentPart.audio_duration_s)}</span>
          </strong>
        )}
        {!isReading && (
          <audio
            key={currentPart.audio_path}
            className="preview-audio"
            controls
            src={urls[currentPart.audio_path]}
            onTimeUpdate={(event) => setAudioLeft(event.target.duration - event.target.currentTime)}
          />
        )}
      </div>
      {page && (
        <div className="exam">
          <div>
            <nav className="page-nav">
              {viewPages.map((item, index) => (
                <button key={item.page_order} aria-pressed={index === pageIndex} onClick={() => setPageIndex(index)}>
                  {index + 1}
                </button>
              ))}
            </nav>
            <img className="page-image" src={urls[page.image_path]} alt={`Página ${pageIndex + 1}`} />
          </div>
          <BubbleSheet
            first={page.first_q}
            last={page.last_q}
            choices={pagePart.choices_count}
            answers={answers}
            onSelect={(question, option) => setAnswers((current) => ({ ...current, [question]: option }))}
          />
        </div>
      )}
    </section>
  )
}
