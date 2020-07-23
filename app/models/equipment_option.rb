class EquipmentOption < ApplicationRecord
  # TODO: Why belongs_to :admin?
  belongs_to :admin
  validates :name, presence: true
  scope :show_options, -> { order(Arel.sql('lower(name) ASC')).all }
end
