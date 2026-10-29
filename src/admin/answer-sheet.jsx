import { useEffect, useState } from 'react'
import { supabase } from '../lib/supabase-client.js'
import { formatBogota } from '../lib/format-date.js'

const SECTIONS = [
  { section: 'listening', title: 'Listening' },
  { section: 'reading', title: 'Reading' },
]

export default function AnswerSheet({ attemptId, studentName, examId, examTitle, startsAt, onBack }) {
  const [answers, setAnswers] = useState({})
  const [parts, setParts] = useState([])
  const [error, setError] = useState('')

  useEffect(() => {
    const load = async () => {
      const [answersResult, partsResult] = await Promise.all([
        supabase.from('answers').select('question_number, selected_option').eq('attempt_id', attemptId),
        supabase.from('exam_parts').select('section, first_q, last_q').eq('exam_id', examId).order('part'),
      ])
      const failed = [answersResult, partsResult].find((result) => result.error)
      if (failed) {
        setError(failed.error.message)
        return
      }
      setAnswers(Object.fromEntries(answersResult.data.map((answer) => [answer.question_number, answer.selected_option])))
      setParts(partsResult.data)
    }
    load()
  }, [attemptId, examId])

  const questionsOf = (section) =>
    parts
      .filter((part) => part.section === section)
      .flatMap((part) => Array.from({ length: part.last_q - part.first_q + 1 }, (_, index) => part.first_q + index))
  const total = parts.reduce((sum, part) => sum + part.last_q - part.first_q + 1, 0)

  return (
    <section className="answer-sheet">
      <div className="actions no-print">
        <button onClick={onBack}>← Volver</button>
        <button onClick={() => window.print()}>Imprimir</button>
      </div>
      {error && <p role="alert">{error}</p>}
      <h2>Hoja de respuestas</h2>
      <p>
        <strong>Estudiante:</strong> {studentName}
        <br />
        <strong>Simulacro:</strong> {examTitle}
        <br />
        <strong>Fecha:</strong> {formatBogota(startsAt)}
        <br />
        <strong>Respondidas:</strong> {Object.keys(answers).length} de {total}
      </p>
      {SECTIONS.map(({ section, title }) => (
        <div key={section}>
          <h3>{title}</h3>
          <div className="sheet-grid">
            {questionsOf(section).map((question) => (
              <span key={question}>
                {question}. <strong>{answers[question] ?? '—'}</strong>
              </span>
            ))}
          </div>
        </div>
      ))}
    </section>
  )
}
