# frozen_string_literal: true

namespace :admin do
  get "/", as: "index", action: "index"

  resources :announcements

  resources :deleted_repositories, only: :index do
    resource :restoration, only: :create, module: :deleted_repositories
  end

  resources :cc_moneys, only: :index do
    resource :claim_email, only: :create, controller: "cc_money_claim_emails"
    resource :purchase_email, only: :update, controller: "cc_money_purchase_emails"
  end

  resources :job_service_groups, only: %i[new create edit update destroy]
  resources :job_services, only: %i[new create edit update destroy]
  resources :job_options, only: %i[new create edit update destroy]
  resources :job_types, only: %i[new create edit update]

  namespace :report_generator do
    get "/", as: "index", action: "index"
    post "/generate", as: "generate", action: "generate"
    get "/generate_spreadsheet",
        as: "generate_spreadsheet",
        action: "generate_spreadsheet",
        format: :xlsx
  end

  namespace :cdel_reports do
    get "/", as: "index", action: "index"
    get "/generate_output", as: "generate", action: "generate", format: :csv
  end

  resource :design_day, only: %i[show update] do
    collection do
      get :data
    end
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
      patch :rename_user
      #   patch "mass_update_roles", to: "users#mass_update_roles"
    end
    member do
      patch :change_email
    end
    resource :activation, only: %i[create destroy], module: :users
    # member do
    #   get "fetch_spaces"
    #   patch "update_spaces"
    # end
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
    patch "/edit/:id/rename", 
         as: "update_sub_space", 
         action: "update_sub_space"

    collection do
      post :update_max_capacity
      patch :update_keycode
      patch :add_space_manager
      patch :remove_space_manager
      put :update_staff_needed_calendars
    end
  end

  namespace :add_new_staff do
    get "/", as: "index", action: "index"
  end
  
  resources :pi_readers, only: %i[create update]

  resources :trainings, except: :show

  resources :skills, except: :show

  resources :drop_off_locations, except: :show

  resources :contact_infos, except: :show

  resources :time_periods, except: [:show]

  resources :training_sessions, only: %i[index update destroy]

  resources :settings, only: [:index] do
    collection do
      post "add_category"
      post "add_area"

      # post 'rename_category'
      patch "update_job_order_processed"
      patch "update_print_failed_message"
      post "remove_category"
      post "remove_area"
      post "add_equipment"
      post "rename_equipment"
      post "remove_equipment"
      post "remove_pi"
      post "add_course"
      delete "remove_course"
      patch "rename_course"
      patch "pin_unpin_repository"
    end
  end

  resources :certifications, only: %i[show update destroy] do
    collection do
      get :open_modal
      get :demotions
    end
  end

  resources :keys do
    get :assign
    patch :assign_key
    get :revoke
    patch :revoke_key
    get :history
    collection do
      get :requests
      patch :approve_key_request
      patch :deny_key_request
    end
  end

  resources :key_transactions, only: %i[index show edit update]

  resources :teams, only: %i[index show new edit create update] do
    member do
      patch :add_member, action: :add_member, as: :add_member
      patch "promote_member/:member_id",
            action: :promote_member,
            as: :promote_member
      patch "demote_member/:member_id",
            action: :demote_member,
            as: :demote_member
      delete "remove_member/:member_id",
             action: :remove_member,
             as: :remove_member
    end
  end

  namespace :uni_programs do
    get "/", as: "index", action: "index"
    get "/current_programs",
        as: "current_programs",
        action: "current_programs",
        format: :csv
    post "import_programs"
  end

  resources :calendar, only: :index do
    collection do
      get 'unavailabilities_json/:id', to: 'calendar#unavailabilities_json', as: :unavailabilities_json
      get 'imported_calendars_json/:id', to: 'calendar#imported_calendars_json', as: :imported_calendars_json
      post :update_color
    end
  end

  resources :events, only: [:create, :update] do
    collection do
      get 'json/:id', to: 'events#json', as: :json
      patch :publish
      delete :delete_drafts
      post :copy
    end
    member do
      patch :publish
      delete :delete_with_scope
    end
    resource :publication, only: :destroy, module: :events
  end

  resources :memberships, only: [:index, :update]
  
end
# For singular routes
resolve('DesignDay') {[:admin, :design_day]}
