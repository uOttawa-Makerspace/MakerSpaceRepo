class Certification < ActiveRecord::Base
  belongs_to :user
  belongs_to :training_session
  has_one :space, through: :training_session

  validates :user, presence: { message: "A user is required." }
  validates :training_session, presence: { message: "A training session is required." }
  validate :unique_cert


  def training
    begin
      training = self.training_session.training.name
    rescue NoMethodError => e
      training = nil
    end
    return training
  end

  def trainer
    begin
      trainer = self.training_session.user.name
    rescue NoMethodError => e
      trainer = nil
    end
    return trainer
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
    begin
      @user_certs = self.user.certifications
    rescue NoMethodError => e
      @user_certs = nil
    end
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

  scope :between_dates_picked, ->(start_date , end_date){ where('created_at BETWEEN ? AND ? ', start_date , end_date) }

end
