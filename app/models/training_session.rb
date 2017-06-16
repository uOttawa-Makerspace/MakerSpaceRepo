class TrainingSession < ActiveRecord::Base
  belongs_to :training
  belongs_to :user
  has_and_belongs_to_many :users
  has_many :certifications

  validates :training, presence: { message: "A training subject is required"}
  validates :user, presence: { message: "A trainer subject is required"}
  validate :is_staff

  def is_staff
    errors.add(:string, "user must be staff") unless self.user.staff?
  end
end
