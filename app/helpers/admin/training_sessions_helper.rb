# frozen_string_literal: true

module Admin::TrainingSessionsHelper
  def search(search)
    search.split('=').last.gsub('+', ' ').gsub('%20', ' ') if search.present?
  end
end
