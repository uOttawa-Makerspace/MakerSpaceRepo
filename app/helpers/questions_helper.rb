# frozen_string_literal: true

module QuestionsHelper
  def return_answer_border_color(answer)
    answer.correct ? "border-success" : "border-danger"
  end

  # Level choices shown in the reader's language; the stored value stays the English level name.
  def question_level_options(levels)
    levels.map { |level| [t(level, scope: "questions.levels"), level] }
  end
end
