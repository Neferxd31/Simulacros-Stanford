import { useState } from 'react'
import ExamReview from './exam-review.jsx'
import SessionsPanel from './sessions-panel.jsx'

export default function AdminHome() {
  const [tab, setTab] = useState('sessions')
  return (
    <>
      <h1 className="page-title no-print">Panel docente</h1>
      <nav className="tabs no-print">
        <button aria-pressed={tab === 'sessions'} onClick={() => setTab('sessions')}>
          Sesiones
        </button>
        <button aria-pressed={tab === 'exams'} onClick={() => setTab('exams')}>
          Simulacros
        </button>
      </nav>
      {tab === 'sessions' ? <SessionsPanel /> : <ExamReview />}
    </>
  )
}
