# frozen_string_literal: true

Rails.application.routes.draw do
  resources :price_rules, only: %i[index new create destroy edit update]
  resources :discount_codes, only: %i[new index create]
  resources :coupon_codes, only: %i[index new create destroy edit update]

  resources :custom_webhooks do
    collection { post :orders_paid }
  end

  resources :videos, only: %i[index new create destroy]
  get "videos/:id/download/:filename",
      to: "videos#download",
      constraints: {
        filename: /.+/
      },
      as: "download_video"

  require "sidekiq/web"
  Sidekiq::Web.use Rack::Auth::Basic do |username, password|
    get_username =
      Rails.application.credentials[Rails.env.to_sym][:sidekiq][:username] ||
        "adam"
    get_password =
      Rails.application.credentials[Rails.env.to_sym][:sidekiq][:password] ||
        "Password1"
    username == get_username && password == get_password
  end
  mount Sidekiq::Web => "/sidekiq"

  mount StripeEvent::Engine, at: "/stripe/webhooks"

  resources :project_kits, only: %i[index new create destroy] do
    get :mark_delivered
    collection { get :populate_kit_users }
  end

  resources :cc_moneys, only: [:index] do
    collection do
      get :redeem
      get :link_cc_to_user
    end
  end

  resources :carts, only: [:index]
  resources :order_items, only: %i[create update destroy] do
    get :revoke, path: "revoke"
  end

  resources :orders, only: %i[index create destroy]

  get "/saml/auth" => "saml_idp#login"
  get "/saml/metadata" => "saml_idp#metadata"
  get "/saml/wiki_metadata" => "saml_idp#wiki_metadata"
  post "/saml/auth" => "saml_idp#auth"

  resources :print_orders,
            only: %i[index create update new destroy edit show] do
    get :edit_approval
    collection do
      get :index_new
      patch :update_submission
    end
  end

  resources :job_orders, only: %i[index create update new destroy] do
    get :steps
    get :quote_modal
    get :timeline_modal
    get :completed_email_modal
    get :decline_modal
    get :invoice
    patch :quote
    patch :steps
    patch :user_approval
    patch :start_processing
    patch :processed
    patch :paid
    patch :picked_up
    patch :resend_quote_email
    collection do
      get :admin
      get :settings
      get :user_magic_approval
      get :pay
      get :stripe_success
      get :stripe_cancelled
      patch :user_magic_approval_confirmation
      post "/new" => "job_orders#new"
      patch "/new" => "job_orders#new"
    end
  end

  resources :project_proposals do
    collection do
      post :create_revision
      post :approve
      post :decline
      get :join_project_proposal
      get :unjoin_project_proposal
      get :projects_assigned
      get :projects_completed
      get :user_projects
      delete :destroy, path: "destroy/:id", as: "destroy"
    end
  end

  resources :printers do
    collection do
      get :staff_printers
      get :staff_printers_updates
      patch :link_printer_to_user
    end
  end

  root "static_pages#home"

  # STATIC PAGES
  namespace :static_pages, path: "/", as: nil do
    get "forgot_password"
    patch "reset_password"
    get "terms_of_service", as: "tos"
    get "hours"
    get "about"
    get "contact"
    get "calendar"
    get "report_repository/:repository_id",
        as: "report_repository",
        action: "report_repository"
    get "volunteer_program_info"
    get "development_program_info"
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
    get "likes"
    get "category/:slug", as: "category", action: "category"
    get "category/:slug/featured", as: "featured", action: "featured"
    get "equipment/:slug", as: "equipment", action: "equipment"
  end

  # TEMPLATE
  namespace :template do
    get "file"
    get "category"
    get "equipment"
    get "certification"
    get "comment"
  end

  # SESSION
  namespace :sessions, path: "/", as: nil do
    post "login_authentication"
    get "logout"
    get "login"
    get "resend_email_confirmation"
    get "check_signed_in"
  end

  # GITHUB
  namespace :github do
    get "authorize"
    get "callback"
    get "unauthorize"
    get "repositories"
  end

  # SETTING
  namespace :settings do
    get "profile"
    get "admin"
  end

  get "help", to: "help#main"
  post "send_email", to: "help#send_email"

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

  namespace :admin do
    get "/", as: "index", action: "index"

    resources :announcements

    resources :badge_templates, only: %i[index edit update]

    resources :job_service_groups,
              only: %i[index new create edit update destroy]
    resources :job_services, only: %i[index new create edit update destroy]
    resources :job_options, only: %i[index new create edit update destroy]
    resources :job_type_extras, only: %i[index new create edit update destroy]
    resources :job_types, only: %i[index new create edit update]

    get "manage_badges"

    namespace :report_generator do
      get "/", as: "index", action: "index"
      post "/generate", as: "generate", action: "generate", format: :xlsx
      get :popular_hours
      get :popular_hours_per_period
    end

    resources :users, only: %i[index edit update show] do
      collection do
        get "search"
        #post 'bulk_add_certifications'
        patch "set_role"
        delete "delete_repository"
        delete "delete_user"
        patch "restore_user"
        put "toggle_lock_user"
        get "manage_roles"
      end
    end

    resources :spaces, only: %i[index create edit] do
      delete "/edit/", as: "destroy", action: "destroy"
      post "/edit/", as: "update_name", action: "update_name"
      put "/edit/", as: "create_sub_space", action: "create_sub_space"
      patch "/edit/:sub_space_id",
            as: "set_max_booking_duration",
            action: "set_max_booking_duration"
      patch "/edit/:sub_space_id/max_automatic_approval_hour",
            as: "set_max_automatic_approval_hour",
            action: "set_max_automatic_approval_hour"

      delete "/edit/:id", as: "delete_sub_space", action: "delete_sub_space"
      put "/edit/:id",
          as: "change_sub_space_approval",
          action: "change_sub_space_approval"
      post "/edit/:id",
           as: "change_sub_space_default_public",
           action: "change_sub_space_default_public"

      collection do
        post :update_max_capacity
        post :add_space_hours
        delete :delete_space_hour
        post :add_training_levels
        put :update_staff_needed_calendars
      end
    end

    namespace :add_new_staff do
      get "/", as: "index", action: "index"
    end

    resources :shifts, except: %i[new show] do
      collection do
        get :shifts
        get :get_availabilities
        get :get_shifts
        get :get_staff_needed
        get :get_external_staff_needed
        get :get_shift
        get :pending_shifts
        get :shift_suggestions
        get :ics
        post :update_color
        post :confirm_shifts
        post :clear_pending_shifts
        post :copy_to_next_week
      end
    end

    resources :pi_readers, only: [:update]

    resources :trainings

    resources :skills

    resources :drop_off_locations

    resources :course_names

    resources :contact_infos

    resources :time_periods, except: [:show]

    resources :training_sessions do
      get "/", as: "index", action: "index"

      member { patch "update" }
    end

    resources :settings, only: [:index] do
      collection do
        post "add_category"
        post "add_area"
        post "add_printer"
        # post 'rename_category'
        patch "update_job_order_processed"
        post "remove_category"
        post "remove_area"
        post "remove_printer"
        post "add_equipment"
        post "rename_equipment"
        post "remove_equipment"
        post "submit_pi"
        post "remove_pi"
        get "pin_unpin_repository"
      end
    end

    resources :certifications, only: %i[update destroy] do
      collection do
        get :open_modal
        get :demotions
        get :search_demotions
      end
    end
  end

  namespace :staff do
    resources :training_sessions do
      get "/", as: "index", action: "index", on: :collection
      member do
        post "certify_trainees"
        delete "revoke_certification"
        get "training_report"
      end
    end
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
    get "sign_out_all_users"
    get :user_profile
    get :populate_users
    post :import_excel
    get :refresh_capacity
    get :refresh_tables
  end

  resources :sub_space_booking, only: %i[index create] do
    put :decline
    put :approve
    put :publish
    get :edit
    patch :update
    delete :delete, path: "delete/:sub_space_booking_id"
    collection do
      put :request_access
      put :deny_access
      put :approve_access
      get :bookings
      get :users
    end
  end

  resources :development_programs, only: [:index] do
    collection do
      get :join_development_program
      get :skills
    end
  end

  resources :badges, only: [:index] do
    collection do
      get :admin
      get :new_badge
      get :revoke_badge
      get :populate_badge_list
      get :certify
      get "grant", as: "grant_badge", action: "grant_badge"
      get :reinstate
      get :update_badge_data
      get :update_badge_templates
      get :populate_grant_users
      get :populate_revoke_users
    end
  end

  resources :proficient_projects do
    collection do
      get :join_development_program
      get :requests
      get :open_modal
      get :complete_project
      get :approve_project
      get :revoke_project
      get :generate_acquired_badge
    end
  end

  resources :learning_area do
    collection do
      get :open_modal
      put :reorder
    end
  end

  resources :learning_module_track, only: %i[index] do
    collection do
      get :start
      get :completed
    end
  end

  resources :project_requirements, only: %i[create destroy]

  resources :volunteers, only: [:index] do
    collection do
      get :emails
      get :volunteer_list
      get :join_volunteer_program
      get :my_stats
      get :calendar
      get :shadowing_shifts
      get :delete_event
      get :create_event
      get :new_event
      get :populate_users
    end
  end

  resources :questions do
    collection do
      delete :delete_individually
      delete :remove_answer
      post :add_answer
    end
  end

  resources :staff_availabilities, except: :show do
    collection { get :get_availabilities }
  end

  resources :exams, only: %i[index create show destroy] do
    collection do
      get :finish_exam
      get :create_from_training
      get :create_for_single_user
    end
  end

  resources :exam_responses, only: [:create]

  resources :volunteer_tasks do
    collection do
      get :my_tasks
      get :complete_task
    end
  end

  resources :volunteer_task_requests, only: [:index] do
    collection do
      get :create_request
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

  resources :staff_spaces do
    collection do
      post :change_space_list
      post :bulk_add_users
    end
  end

  # namespace :help do
  #   get 'main', path: '/'
  # end
  # get 'repositories', to: 'repositories#index'
  post "vote/:comment_id", as: "vote", action: "vote", to: "users#vote"

  # USER RESOURCES
  resources :users, path: "/", param: :username, except: :edit do
    collection do
      get :resend_confirmation
      get :confirm_edited_email
      get :reset_password_form
      patch :reset_password_confirmation
      get :confirm
      post :change_programs
      post :create, path: "/new"
      get :remove_avatar
      post :flag
      post :unflag
      get :change_email
      put :remove_flag
      get :unlock_account
    end

    get "likes", on: :member
    patch "change_password", on: :member
  end

  # REPOSITORY RESOURCES
  resources :repositories,
            path: "/:user_username",
            param: :id,
            except: :index,
            constraints:
              lambda { |request|
                User.find_by(username: request.params[:user_username]).present?
              } do
    post "add_like", on: :member
    collection do
      get ":id/download_files",
          as: "download_files",
          action: "download_files",
          constraints: {
            id: %r{[^/]+}
          }
      patch :link_to_pp
      patch :add_owner
      patch :remove_owner
    end
    member do
      get "/password_entry", as: "password_entry", action: "password_entry"
      post "pass_authenticate"
    end
  end
  get "/repositories/populate_users", to: "repositories#populate_users"

  namespace :makes, path: "makes/:user_username/:id" do
    post "create"
    get "new"
  end

  namespace :comments do
    post :create, path: "/:id"
    delete :destroy, path: "/:id/destroy"
  end

  namespace :quick_access_links do
    post :create
    post :update, path: "update/:id", as: "update"
    delete :delete, path: "delete/:id", as: "delete"
  end
end
