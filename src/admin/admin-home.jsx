import { useState } from 'react'
import ExamReview from './exam-review.jsx'
import SessionsPanel from './sessions-panel.jsx'
import StudentsPanel from './students-panel.jsx'

const TABS = { sessions: SessionsPanel, students: StudentsPanel, exams: ExamReview }

export default function AdminHome() {
  const [tab, setTab] = useState('sessions')
  const Panel = TABS[tab]
  return (
    <>
      <h1 className="page-title no-print">Panel docente</h1>
      <nav className="tabs no-print">
        <button aria-pressed={tab === 'sessions'} onClick={() => setTab('sessions')}>
          Sesiones
        </button>
        <button aria-pressed={tab === 'students'} onClick={() => setTab('students')}>
          Estudiantes
        </button>
        <button aria-pressed={tab === 'exams'} onClick={() => setTab('exams')}>
          Simulacros
        </button>
      </nav>
      <Panel />
    </>
  )
}
