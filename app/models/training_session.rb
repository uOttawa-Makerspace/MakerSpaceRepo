class TrainingSession < ActiveRecord::Base
  belongs_to :training
  belongs_to :user

  has_and_belongs_to_many :users, :uniq => true
  has_many :certifications, dependent: :destroy
  has_one :space, through: :training

  validates :training, presence: { message: "A training subject is required"}
  validates :user, presence: { message: "A trainer is required"}
  validate :is_staff

  before_save :check_course

  def is_staff
    errors.add(:string, "user must be staff") unless self.user.staff?
  end

  def courses
    ['GNG2101', 'GNG2501', 'GNG1103', 'GNG1503', 'MCG4143', 'no course']
  end

  def completed?
    return self.certifications.length > 0
  end

  private

  def check_course
    if self.course == 'no course'
      self.course = nil
    end
  end

  scope :between_dates_picked, ->(start_date , end_date){ where('created_at BETWEEN ? AND ? ', start_date , end_date) }

end
