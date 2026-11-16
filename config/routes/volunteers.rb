# frozen_string_literal: true

resources :volunteers, only: [:index] do
  collection do
    get :emails
    get :volunteer_list
    post :join_volunteer_program
    get :my_stats
    get :transcript
    get :calendar
    get :shadowing_shifts
    delete :delete_event
    post :create_event
    get :new_event
    get :populate_users
  end
end
