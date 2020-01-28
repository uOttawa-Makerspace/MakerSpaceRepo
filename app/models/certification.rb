class Certification < ActiveRecord::Base
  belongs_to :user
  belongs_to :training_session
  has_one :space, through: :training_session

  validates :user, presence: { message: "A user is required." }
  validates :training_session, presence: { message: "A training session is required." }
  validate :unique_cert
  has_one :training, through: :training_session

  scope :between_dates_picked, ->(start_date , end_date){ where('created_at BETWEEN ? AND ? ', start_date , end_date) }

  def trainer
    return self.training_session.user.name
  end

  def out_of_date?
    return self.updated_at < 2.years.ago
  end


  def self.to_csv (attributes)
    CSV.generate do |csv|
      attributes.each do |row|
        csv << row
      end
    end
  end

  def unique_cert
    @user_certs = self.user.certifications
    if @user_certs
      @user_certs.each do |cert|
        if (cert.training.id == self.training.id) && (cert.level == self.level)
          errors.add(:string, "Certification already exists.")
          return false
        end
      end
    else
      errors.add(:string, "Something went wrong.")
      return false
    end
    return true
  end

  def self.certify_user(training_session_id, user_id)
    self.create(user_id: user_id, training_session_id: training_session_id)
  end

  def get_badge_path
    self.
  end

end
