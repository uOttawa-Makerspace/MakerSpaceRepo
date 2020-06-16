# frozen_string_literal: true

class CategoryOption < ApplicationRecord
  belongs_to :admin
  has_many :categories

  validates :name, presence: true

  scope :show_options, -> { order(Arel.sql('lower(name) ASC')).all }
end
