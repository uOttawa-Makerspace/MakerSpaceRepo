class Training < ActiveRecord::Base
  belongs_to :space
  has_many :training_sessions, dependent: :destroy
  validates :name, presence: true, uniqueness: true
end
