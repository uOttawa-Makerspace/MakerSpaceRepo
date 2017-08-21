class Space < ActiveRecord::Base
  has_many :pi_readers
  has_many :lab_sessions, through: :pi_readers
  has_many :users, through: :lab_sessions
  has_many :trainings
  has_many :training_sessions, through: :trainings

  validates :name,  presence: { message: "A name is required for the space"}, uniqueness: { message: "Space already exists"}

  def signed_in_users
    return self.lab_sessions.where("sign_out_time > ?", Time.now).map(&:user)
  end

end
