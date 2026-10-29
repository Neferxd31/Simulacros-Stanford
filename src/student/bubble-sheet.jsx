const OPTIONS = ['A', 'B', 'C', 'D']

// first/last are null on pages without questions (instructions)
export default function BubbleSheet({ first, last, choices, answers, onSelect }) {
  if (!first) {
    return (
      <aside className="bubbles">
        <p>Esta página no tiene preguntas.</p>
      </aside>
    )
  }
  const questions = Array.from({ length: last - first + 1 }, (_, index) => first + index)
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
