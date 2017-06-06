class Certification < ActiveRecord::Base
  belongs_to :user
  belongs_to :staff
  belongs_to :training_session
end
