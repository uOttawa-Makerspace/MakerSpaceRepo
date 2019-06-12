class RequireTraining < ActiveRecord::Base
  belongs_to :training
  belongs_to :volunteer_task
end
