class Space < ActiveRecord::Base
  has_many :users
  has_many :lab_sessions
  has_many :pi_readers
  has_many :trainings

  validates :name,  presence: { message: "A name is required for the space"}, uniquness: { message: "Space already exists"}

end
