class EquipmentOption < ActiveRecord::Base
  belongs_to :admin
  validates :name, presence: true
end
