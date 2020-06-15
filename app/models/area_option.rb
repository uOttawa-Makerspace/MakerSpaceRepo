# frozen_string_literal: true

class AreaOption < ApplicationRecord
  validates :name, presence: true
  scope :show_options, -> { order('lower(name) ASC').all }
end
