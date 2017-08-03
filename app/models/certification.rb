class Certification < ActiveRecord::Base
  belongs_to :user
  belongs_to :training_session

  validates :user, presence: { message: "A user is required." }
  validates :training_session, presence: { message: "A training session is required." }
  validate :unique_cert, on: :create

  def training
    return self.training_session.training.name
  end

  def trainer
    return self.training_session.user.name
  end

  def unique_cert
    @user_certs = self.user.certifications
    @user_certs.each do |cert|
      if cert.training == self.training
        errors.add(:string, "Certification already exists.")
      end
    end
  end

end
