# frozen_string_literal: true

resources :key_requests, only: %i[index new create show] do
  get :steps
  patch :steps, action: :update_steps
end

resources :key_certifications, only: %i[show update] do
  member do
    delete "destroy_pdf/:file_number", action: :destroy_pdf, as: :destroy_pdf
  end
end

namespace :staff do
  resources :training_sessions, except: :edit do
    member do
      post "certify_trainees"
      delete "revoke_certification"
      get "training_report"
    end
  end
  resources :proficient_project_sessions, only: [:show]

  resources :my_calendar, only: :index do
    collection do
      get 'json/:id', to: 'my_calendar#json', as: :json
    end
  end
  resources :unavailabilities, except: %i[new edit show] do
    collection do
      get :json
      patch :update_external_unavailabilities
    end
    member do
      delete :delete_with_scope
    end
  end
  resource :tap_box_console, only: [:show], controller: "tap_box_console"
end

namespace :staff_dashboard do
  get "/", as: "index", action: "index"
  get "search"
  get "present_users_report"
  put "/change_space", as: "change_space", action: "change_space"
  put "/add_users", as: "sign_in_users", action: "sign_in_users"
  put "/remove_users", as: "sign_out_users", action: "sign_out_users"
  put "link_rfid"
  put "unlink_rfid"
  post "sign_out_all_users"
  get :user_profile
  get :populate_users
  post :import_excel
  get :refresh_capacity
  get :refresh_tables
  patch :add_signed_in_users_to_teams
end

resources :sub_space_booking, only: %i[index create] do
  put :decline
  put :approve
  put :publish
  get :edit
  patch :update
  delete :delete, path: "delete/:sub_space_booking_id"
  member { delete :delete_remaining_recurring }
  collection do
    # for /approve and /decline
    put :bulk_approve_decline
    put :request_access
    put :deny_access
    put :approve_access
    put :bulk_approve_access
    get :bookings
    get :users
    get :get_sub_space_booking
  end
end

post "/google/calendar/webhook", to: "google_calendar#webhook"
