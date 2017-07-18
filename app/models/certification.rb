class Certification < ActiveRecord::Base
  belongs_to :user

  # validate unique_cert
  #
  # def unique_cert
  #   @user_certs = self.user.certifications
  #   @user_certs.each do |cert|
  #     if cert.training == self.training
  #       errors.add(:string, "certification already exists")
  #     end
  #   end
  # end

end
