class TrainingSession < ActiveRecord::Base
  belongs_to :training
  belongs_to :user

  validates :training, presence: true
  validates :user,     presence: true
  validate :is_staff

  def is_admin
    errors.add(:string, "user must be staff") if self.user.role != "staff"
  end
end
