class ProjectJoin < ActiveRecord::Base
  belongs_to :project_proposal
  belongs_to :user

  validates_uniqueness_of :user_id, scope: :project_proposal_id
end
