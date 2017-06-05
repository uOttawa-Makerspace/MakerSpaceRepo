class TrainingSession < ActiveRecord::Base
  has_one :staff
  has_many :users

  validates :staff_id, presence: :ture
  validates :name, presence: :true
end
