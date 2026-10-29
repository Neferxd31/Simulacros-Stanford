import { useCallback, useEffect, useState } from 'react'
import { supabase } from '../lib/supabase-client.js'
import { formatSeconds } from '../lib/format-date.js'

const STATUS_LABELS = { draft: 'Borrador', approved: 'Aprobado', archived: 'Archivado' }

export default function ExamReview() {
  const [exams, setExams] = useState([])
  const [examId, setExamId] = useState(null)
  const [error, setError] = useState('')

  const loadExams = useCallback(
    () =>
      supabase
        .from('exams')
        .select('id, title, status')
        .order('id')
        .then(({ data, error: loadError }) => {
          if (loadError) {
            setError(loadError.message)
            return
          }
          setExams(data)
        }),
    [],
  )

  useEffect(() => {
    loadExams()
  }, [loadExams])

  const setStatus = async (id, status) => {
    const { error: updateError } = await supabase.from('exams').update({ status }).eq('id', id)
    if (updateError) {
      setError(updateError.message)
      return
    }
    loadExams()
  }

  const exam = exams.find((item) => item.id === examId)
  if (exam) return <ExamDetail exam={exam} onBack={() => setExamId(null)} onSetStatus={setStatus} />

  return (
    <section>
      <h2>Simulacros</h2>
      {error && <p role="alert">{error}</p>}
      <ul className="list">
        {exams.map((item) => (
          <li key={item.id}>
            <span>
              {item.title} · {STATUS_LABELS[item.status]}
            </span>
            <button onClick={() => setExamId(item.id)}>Revisar</button>
          </li>
        ))}
      </ul>
    </section>
  )
}

function ExamDetail({ exam, onBack, onSetStatus }) {
  const [pages, setPages] = useState([])
  const [parts, setParts] = useState([])
  const [urls, setUrls] = useState({})
  const [error, setError] = useState('')

  useEffect(() => {
    const load = async () => {
      const [pagesResult, partsResult] = await Promise.all([
        supabase.from('exam_pages').select('*').eq('exam_id', exam.id).order('page_order'),
        supabase.from('exam_parts').select('*').eq('exam_id', exam.id).order('part'),
      ])
      const failed = [pagesResult, partsResult].find((result) => result.error)
      if (failed) {
        setError(failed.error.message)
        return
      }
      const paths = [
        ...pagesResult.data.map((page) => page.image_path),
        ...partsResult.data.filter((part) => part.audio_path).map((part) => part.audio_path),
      ]
      const { data, error: signError } = await supabase.storage.from('exams').createSignedUrls(paths, 3600)
      if (signError) {
        setError(signError.message)
        return
      }
      setPages(pagesResult.data)
      setParts(partsResult.data)
      setUrls(Object.fromEntries(data.map((item) => [item.path, item.signedUrl])))
    }
    load()
  }, [exam.id])

  return (
    <section>
      <button onClick={onBack}>← Volver</button>
      <h2>
        {exam.title} · {STATUS_LABELS[exam.status]}
      </h2>
      <p>
        Revisa el orden, que nada quede recortado, la legibilidad, que no queden pistas (claves, audioscripts) y que el
        rango de preguntas de cada página coincida.
      </p>
      <div className="actions">
        {exam.status !== 'approved' && (
          <button className="primary" onClick={() => onSetStatus(exam.id, 'approved')}>
            Aprobar
          </button>
        )}
        {exam.status !== 'archived' && <button onClick={() => onSetStatus(exam.id, 'archived')}>Archivar</button>}
        {exam.status !== 'draft' && <button onClick={() => onSetStatus(exam.id, 'draft')}>Volver a borrador</button>}
      </div>
      {error && <p role="alert">{error}</p>}

      <h3>Audios</h3>
      {parts
        .filter((part) => part.audio_path)
        .map((part) => (
          <div key={part.part} className="audio-row">
            <span>
              Parte {part.part} · {formatSeconds(part.audio_duration_s)}
            </span>
            <audio controls preload="none" src={urls[part.audio_path]} />
          </div>
        ))}

      <h3>Páginas</h3>
      <div className="contact-sheet">
        {pages.map((page) => (
          <a key={page.page_order} href={urls[page.image_path]} target="_blank" rel="noreferrer">
            <img src={urls[page.image_path]} alt={`Página ${page.page_order}`} loading="lazy" />
            <span>
              {page.page_order}. Parte {page.part} · {page.first_q ? `${page.first_q}-${page.last_q}` : 'Instrucciones'}
            </span>
          </a>
        ))}
      </div>
    </section>
  )
}
