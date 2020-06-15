# frozen_string_literal: true

json.extract! project_proposal, :id, :user_id, :admin_id, :approved, :title, :description, :youtube_link, :created_at, :updated_at,
              :username, :email, :client, :area, :client_type
json.url project_proposal_url(project_proposal, format: :json)
