class Space < ActiveRecord::Base
  has_many :pi_readers
  has_many :lab_sessions, through: :pi_readers
  has_many :users, through: :lab_sessions
  has_many :trainings

  validates :name,  presence: { message: "A name is required for the space"}, uniqueness: { message: "Space already exists"}

  def signed_in_users
    return self.lab_sessions.where("sign_out_time > ?", Time.now).map(&:user)
  end

  def recently_signed_out_users
    return self.lab_sessions.where(["(sign_out_time < ?) AND (sign_out_time > ?)", Time.now, 1.day.ago]).limit(40).map(&:user)
  end

end
