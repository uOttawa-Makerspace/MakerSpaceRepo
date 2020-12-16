# frozen_string_literal: true

module QuestionsHelper
  def return_border_color(answer)
    answer.correct ? 'border-success' : 'border-danger'
  end
end
