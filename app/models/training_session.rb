class TrainingSession < ActiveRecord::Base
  belongs_to :training
  belongs_to :user
  has_and_belongs_to_many :users
  has_many :certifications

  validates :training, presence: true
  validates :user,     presence: true
  validate :is_staff

  def is_staff
    errors.add(:string, "user must be staff") if self.user.role != "staff"
  end
end
