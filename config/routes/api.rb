# frozen_string_literal: true

# JSON API for the React frontends: Bearer auth, no cookies. Contracts: doc/api/v1/.
namespace :api do
  namespace :v1 do
    resource :session, only: %i[create show destroy] do
      post :refresh
    end
    get "users", to: "users#index"
    get "users/:username", to: "users#show", constraints: { username: %r{[^/]+} }
    # Strict integer ids at the router (UsersController#find_user! checks again).
    patch "users/:id/role", to: "users#role", constraints: { id: /\d+/ }
    put "users/:id/programs", to: "users#programs", constraints: { id: /\d+/ }
    get "spaces", to: "spaces#index"
    get "me/space", to: "my_spaces#show"
    put "me/space", to: "my_spaces#update"
    get "spaces/:id/presence", to: "presence#show", constraints: { id: /\d+/ }
    post "spaces/:id/presence", to: "presence#create", constraints: { id: /\d+/ }
    delete "spaces/:id/presence/:username", to: "presence#destroy", constraints: { id: /\d+/, username: %r{[^/]+} }
    get "rfid_cards", to: "rfid_cards#index"
    put "users/:id/rfid", to: "user_rfids#update", constraints: { id: /\d+/ }
    delete "users/:id/rfid", to: "user_rfids#destroy", constraints: { id: /\d+/ }
    post "rfid_taps", to: "rfid_taps#create"
    get "training_sessions", to: "training_sessions#index"
    post "training_sessions", to: "training_sessions#create"
    get "training_session_options", to: "training_session_options#show"
    post "training_sessions/:training_session_id/certifications", to: "training_session_certifications#create",
                                                                  constraints: { training_session_id: /\d+/ }
    get "printer_types", to: "printer_types#index"
    post "printers/:id/assignments", to: "printer_assignments#create", constraints: { id: /\d+/ }
    get "printer_issues", to: "printer_issues#index"
    patch "printer_issues/:id", to: "printer_issues#update", constraints: { id: /\d+/ }
    get "spaces/:id/shifts", to: "shifts#index", constraints: { id: /\d+/ }
    get "design_day", to: "design_days#show", format: false
    post "support_requests", to: "support_requests#create", format: false
    get "contact_infos", to: "contact_infos#index", format: false
    # keep last: unknown /api/v1 paths answer with the JSON 404, not the HTML one
    match "*path", to: "base#route_not_found", via: :all
  end
end
