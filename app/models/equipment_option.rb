class EquipmentOption < ApplicationRecord
  # TODO: Why belongs_to :admin?, optional: true
  belongs_to :admin, optional: true
  validates :name, presence: true
  scope :show_options, -> { order(Arel.sql("lower(name) ASC")).all }
end
