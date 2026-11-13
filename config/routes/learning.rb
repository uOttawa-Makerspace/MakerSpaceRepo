# frozen_string_literal: true

resources :development_programs, only: [:index] do
  collection do
    post :join_development_program
    get :skills
    get :all_badges
  end
end

resources :badges, only: [:index, :show] do
  collection do
    get 'search'
  end
end

resources :proficient_projects do
  get :proficient_project_modal
  collection do
    get :requests
    put :complete_project
    post :approve_project
    post :revoke_project
    get :generate_acquired_badge
  end
end

# Define standalone route before resources to take priority
get '/learning_area/s/:shortcut', to: 'learning_area#show', as: :shortcut_learning_area
resources :learning_area do
  collection do
    put :reorder
    get 'subskill/:subskill', to: 'learning_area#subskill', as: :subskill
  end

  member do
    get :scorm_launch
    post :scorm_commit, defaults: { format: :json }
    post :retry_scorm
    # format: false to preserve dot at URL end, else we lose file extension
    get "scorm_assets/*path", to: "learning_area#serve_scorm_asset", as: :scorm_asset, format: false
  end
end

resources :learning_module_track, only: %i[index] do
  collection do
    post :start
    post :completed
  end
end

resources :project_requirements, only: %i[create destroy]
