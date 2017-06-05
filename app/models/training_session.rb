class TrainingSession < ActiveRecord::Base
  has_one :staff
  has_many :users
end
