class TrainingSession < ActiveRecord::Base

  belongs_to :training
  belongs_to :user #the staff/admin
  has_and_belongs_to_many :users, :uniq => true #the trainees

  has_many :certifications, dependent: :destroy
  has_one :space, through: :training

  validates :training, presence: { message: "A training subject is required"}
  validates :user, presence: { message: "A trainer is required"}
  validate :is_staff

  def is_staff
    errors.add(:string, "user must be staff") unless self.user.staff?
  end

  def courses
    ['GNG2101', 'GNG1103']
  end

end
