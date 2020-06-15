# frozen_string_literal: true

module ProjectProposalsHelper
  def find_project_join(user_id, project_proposal_id)
    ProjectJoin.where(user_id: user_id, project_proposal_id: project_proposal_id).last
  end
end
