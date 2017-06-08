class Training < ActiveRecord::Base
  has_many :training_session, dependent: :destroy
  validates :name, presence: true, uniqueness: true
end
