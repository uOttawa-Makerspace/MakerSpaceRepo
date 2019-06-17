class Skill < ActiveRecord::Base
  belongs_to :user
  validates_uniqueness_of :user_id
end
