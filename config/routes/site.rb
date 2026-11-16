# frozen_string_literal: true

root "static_pages#home"

get "changelog", to: "changelog#index"

# STATIC PAGES
namespace :static_pages, path: "/", as: nil do
  get "forgot_password"
  patch "reset_password"
  get "terms_of_service", as: "tos"
  get "hours"
  get "open_hours"
  get "about"
  get "contact"
  get "calendar"
  post "report_repository/:repository_id",
      as: "report_repository",
      action: "report_repository"
  post "join_team_program"
  get "get_involved"
  get "resources"
  get "labs"
end

# RFID
namespace :rfid do
  get :get_unset_rfids
  post "card_number"
end

# SEARCH PAGES
namespace :search, path: "/", as: nil do
  get "explore"
  get "search"
  get "category/:slug", as: "category", action: "category"
  get "equipment/:slug", as: "equipment", action: "equipment"
end

# TEMPLATE
namespace :template do
  get "file"
  get "category"
  get "equipment"
  get "certification"
end

# SESSION
namespace :sessions, path: "/", as: nil do
  post "login_authentication"
  # GET /logout is kept for MakerRepoApp until it ships POST logout
  # (frontend-api-inventory.md row 3). The site's own UI uses DELETE.
  get "logout"
  match "logout", via: %i[post delete], as: :perform_logout
  get "login"
  get "resend_email_confirmation"
  get "check_signed_in"
end

# SETTING
namespace :settings do
  get "profile"
  get "admin"
end

# LANGUAGE SWITCH
resource :locale, only: :update

# HELP
resource :help, only: [:show, :create], controller: "help"
put "send_email", to: "help#send_email"

# keep index singular, rename path
# don't define second resourece, that breaks HTTP verbs
resources :faqs,
          only: %i[index new create edit update destroy],
          path: "faq" do
  collection { put "reorder" }
end

namespace :licenses do
  get "common_creative_attribution", as: "cca"
  get "common_creative_attribution_share_alike", as: "ccasa"
  get "common_creative_attribution_no_derivatives", as: "ccand"
  get "common_creative_attribution_non_commercial", as: "ccanc"
  get "attribution_non_commercial_share_alike", as: "ancsa"
  get "attribution_non_commercial_no_derivatives", as: "ancnd"
end

namespace :getting_started, path: "getting-started" do
  get "setting-up-account", as: "sua"
  get "creating-repository", as: "cr"
end
