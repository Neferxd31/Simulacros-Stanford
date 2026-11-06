import { useEffect, useState } from 'react'
import { supabase } from '../lib/supabase-client.js'
import { formatBogota } from '../lib/format-date.js'

// Igual que la hoja de respuestas impresa del libro: una página por sección
const SECTIONS = [
  { section: 'listening', title: 'LISTENING COMPREHENSION' },
  { section: 'reading', title: 'READING' },
]
const PART_NAMES = {
  1: 'Photographs',
  2: 'Question-Response',
  3: 'Conversations',
  4: 'Talks',
  5: 'Incomplete Sentences',
  6: 'Text Completion',
  7: 'Reading Comprehension',
}
const OPTIONS = ['A', 'B', 'C', 'D']
const COLUMNS = 4

export default function AnswerSheet({ attemptId, studentName, examId, examTitle, startsAt, onBack }) {
  const [answers, setAnswers] = useState({})
  const [parts, setParts] = useState([])
  const [error, setError] = useState('')

  useEffect(() => {
    const load = async () => {
      const [answersResult, partsResult] = await Promise.all([
        supabase.from('answers').select('question_number, selected_option').eq('attempt_id', attemptId),
        supabase.from('exam_parts').select('part, section, first_q, last_q, choices_count').eq('exam_id', examId).order('part'),
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

  const total = parts.reduce((sum, part) => sum + part.last_q - part.first_q + 1, 0)

  return (
    <section className="answer-sheet">
      <div className="actions no-print">
        <button onClick={onBack}>← Volver</button>
        <button className="primary" onClick={() => window.print()}>
          Imprimir
        </button>
        <span>
          Respondidas: {Object.keys(answers).length} de {total}
        </span>
      </div>
      {error && <p role="alert">{error}</p>}
      {SECTIONS.map(({ section, title }) => (
        <article key={section} className="sheet-page">
          <header className="sheet-band">
            <div className="sheet-student">
              <span>
                Estudiante: <strong>{studentName}</strong>
              </span>
              <span>Fecha: {formatBogota(startsAt)}</span>
            </div>
            <div className="sheet-title">
              <strong>ANSWER SHEET</strong>
              <span>{examTitle}</span>
            </div>
          </header>
          <div className="sheet-body">
            <h3>{title}</h3>
            {parts
              .filter((part) => part.section === section)
              .map((part) => (
                <SheetPart key={part.part} part={part} answers={answers} />
              ))}
          </div>
          <footer className="sheet-foot" />
        </article>
      ))}
    </section>
  )
}

// Las preguntas llenan cuatro columnas de arriba hacia abajo, como en el papel
function SheetPart({ part, answers }) {
  const questions = Array.from({ length: part.last_q - part.first_q + 1 }, (_, index) => part.first_q + index)
  return (
    <div className="sheet-part">
      <h4>
        Part {part.part}: {PART_NAMES[part.part]}
      </h4>
      <div className="sheet-columns" style={{ gridTemplateRows: `repeat(${Math.ceil(questions.length / COLUMNS)}, auto)` }}>
        {questions.map((question) => (
          <div key={question} className="sheet-item">
            <span className="sheet-number">{question}.</span>
            {OPTIONS.slice(0, part.choices_count).map((option) => (
              <span key={option} className={answers[question] === option ? 'sheet-bubble marked' : 'sheet-bubble'}>
                {option}
              </span>
            ))}
          </div>
        ))}
      </div>
    </div>
  )
}
