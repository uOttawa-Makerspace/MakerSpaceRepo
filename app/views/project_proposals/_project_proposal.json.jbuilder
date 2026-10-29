# frozen_string_literal: true

json.extract! project_proposal,
              :id,
              :user_id,
              :admin_id,
              :approved,
              :title,
              :description,
              :youtube_link,
              :created_at,
              :updated_at,
              :area,
              :client_type
json.url project_proposal_path(project_proposal, format: :json)
# D-C58: the submitter's name/email and the client are contact details; only
# the proposal's owner and admins get them.
if owner_or_admin?(project_proposal)
  json.extract! project_proposal, :username, :email, :client
end
