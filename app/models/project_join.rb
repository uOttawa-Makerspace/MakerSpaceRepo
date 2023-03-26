# frozen_string_literal: true

class ProjectJoin < ApplicationRecord
  belongs_to :project_proposal, optional: true
  belongs_to :user, optional: true

  validates :user_id, uniqueness: { scope: :project_proposal_id }
end
