class Training < ActiveRecord::Base
  has_many :training_sessions, dependent: :destroy
  has_many :certifications, through: :training_sessions
  validates :name, presence: true, uniqueness: true
end
