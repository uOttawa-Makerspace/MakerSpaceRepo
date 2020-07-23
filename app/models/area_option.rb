class AreaOption < ApplicationRecord
  validates :name, presence: true
  scope :show_options, -> { order(Arel.sql('lower(name) ASC')).all }
end
