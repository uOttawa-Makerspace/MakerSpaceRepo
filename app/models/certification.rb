class Certification < ActiveRecord::Base
  belongs_to :user
  belongs_to :training_session
  has_one :space, through: :training_session

  validates :user, presence: { message: "A user is required." }
  validates :training_session, presence: { message: "A training session is required." }
  validate :unique_cert

  scope :out_of_date, -> { where('updated_at < ', 2.years.ago) }

  def training
    return self.training_session.training.name rescue nil
  end

  def trainer
    return self.training_session.user.name rescue nil
  end

  def out_of_date?
    return self.updated_at < 2.years.ago
  end

  def unique_cert
    @user_certs = self.user.certifications rescue nil
    if @user_certs
      @user_certs.each do |cert|
        if cert.training == self.training
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

end
