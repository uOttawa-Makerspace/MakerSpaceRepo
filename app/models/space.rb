class Space < ActiveRecord::Base
  has_many :pi_readers
  has_many :lab_sessions, dependent: :destroy
  has_many :users, through: :lab_sessions
  has_many :trainings, dependent: :destroy
  has_many :training_sessions, through: :trainings
  has_many :certifications, through: :training_sessions
  has_many :volunteer_requests
  has_many :volunteer_tasks

  validates :name,  presence: { message: "A name is required for the space"}, uniqueness: { message: "Space already exists"}

  def signed_in_users
    return self.lab_sessions.where("sign_out_time > ?", Time.zone.now).reverse.map(&:user).uniq
  end

  def recently_signed_out_users
    users = self.lab_sessions.where("sign_out_time < ?", Time.zone.now).last(20).map(&:user).uniq
    self.signed_in_users.each do |user|
      users.delete(user)
    end
    return users
  end

end
