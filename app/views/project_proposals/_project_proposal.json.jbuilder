json.extract! project_proposal, :id, :user_id, :admin_id, :approved, :title, :description, :youtube_link, :created_at, :updated_at
json.url project_proposal_url(project_proposal, format: :json)
