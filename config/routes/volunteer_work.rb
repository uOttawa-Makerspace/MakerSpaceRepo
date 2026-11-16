# frozen_string_literal: true

resources :volunteer_tasks do
  collection do
    get :my_tasks
    post :complete_task
  end
end

resources :volunteer_task_requests, only: [:index] do
  collection do
    post :create_request
    put :update_approval
    get :search_pending
    get :search_processed
  end
end

resources :announcements do
  collection { put :dismiss }
end

resources :volunteer_task_joins, only: [:create] do
  collection { post :remove }
end

resources :volunteer_hours, only: %i[index create new edit destroy update] do
  collection do
    get :volunteer_hour_requests
    put :update_approval
    get :volunteer_hour_per_user
  end
end

resources :require_trainings, only: [:create] do
  collection { post :remove_trainings }
end

resources :staff_spaces, only: [] do
  collection { post :bulk_add_users }
end

# :show and :update would take a space ID and use the logged in session user ID
resources :walk_in_safety_sheets, except: %i[new edit destroy]
