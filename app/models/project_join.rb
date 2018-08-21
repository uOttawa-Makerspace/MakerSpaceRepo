class ProjectJoin < ActiveRecord::Base
  belongs_to :project_proposal
  belongs_to :user
end
