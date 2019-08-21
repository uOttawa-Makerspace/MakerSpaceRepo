class Training < ActiveRecord::Base
  has_and_belongs_to_many :spaces
  has_many :training_sessions, dependent: :destroy
  has_many :certifications, through: :training_sessions
  has_many :require_trainings

  validates :name, presence: true, uniqueness: true
  validates :space_id, presence: true

  def self.all_training_names
    self.order(name: :asc).pluck(:name)
  end
end
