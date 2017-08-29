class TrainingSession < ActiveRecord::Base
  belongs_to :training
  belongs_to :user
  has_and_belongs_to_many :users, :uniq => true
  has_many :certifications, dependent: :destroy

  validates :training, presence: { message: "A training subject is required"}
  validates :user, presence: { message: "A trainer is required"}
  validate :is_staff

  def is_staff
    errors.add(:string, "user must be staff") unless self.user.staff?
  end

  def courses
    ['GNG2101', 'GNG1103']
  end

  def self.to_csv (attributes)
    CSV.generate do |csv|
      attributes.each do |row|
        csv << row
      end
    end
  end

end
