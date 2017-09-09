class Training < ApplicationRecord
  has_many :training_session, dependent: :destroy
  validates :name, presence: true, uniqueness: true
  validates :space_id, presence: true

  has_many :certifications, through: :training_sessions
end
