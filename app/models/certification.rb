class Certification < ActiveRecord::Base
  belongs_to :user
  belongs_to :training_session

  validates :user, presence: true
  validates :trainer_id, presence: true
  validates :training, presence: true
  scope :show_options, -> { order("lower(training) ASC").all }

end
