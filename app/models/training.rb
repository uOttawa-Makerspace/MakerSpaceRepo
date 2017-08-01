class Training < ApplicationRecord
  has_many :training_session, dependent: :destroy
  validates :name, presence: true, uniqueness: true
end
