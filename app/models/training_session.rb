class TrainingSession < ActiveRecord::Base
  belongs_to :staff
  has_many :users

  validates :staff, presence: :true

end
