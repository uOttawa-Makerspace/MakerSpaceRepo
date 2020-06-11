# frozen_string_literal: true

class ProjectJoin < ApplicationRecord
  belongs_to :project_proposal
  belongs_to :user

  validates :user_id, uniqueness: { scope: :project_proposal_id }
end
