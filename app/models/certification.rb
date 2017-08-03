class Certification < ActiveRecord::Base
  belongs_to :user
  belongs_to :training_session

  validates :user, presence: true
  validates :training_session, presence: true

  def training
    return self.training_session.training.name
  end

  def trainer
    return self.training_session.user.name
  end
  
  validate unique_cert
  
  def unique_cert
    @user_certs = self.user.certifications
    @user_certs.each do |cert|
      if cert.training == self.training
        errors.add(:string, "certification already exists")
      end
    end
  end

end
