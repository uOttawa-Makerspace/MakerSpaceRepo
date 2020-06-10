Rails.application.routes.draw do
  resources :price_rules, only: [:index, :new, :create, :destroy, :edit, :update]
  resources :discount_codes, only: [:new, :index, :create]
  resources :custom_webhooks do
    collection do
      post :orders_paid
    end
  end

  resources :videos, only: [:index, :new, :create, :destroy]
  get 'videos/:id/download/:filename', to: 'videos#download', constraints: { filename: /.+/ }, as: 'download_video'

  require 'sidekiq/web'
  Sidekiq::Web.use Rack::Auth::Basic do |username, password|
    get_username = Rails.application.secrets.sidekiq_username || "adam"
    get_password = Rails.application.secrets.sidekiq_password || "Password1"
    username == get_username && password == get_password
  end
  mount Sidekiq::Web => '/sidekiq'

  resources :carts, only: [:index]
  resources :order_items, only: [:create, :update, :destroy] do
    get :revoke, path: 'revoke'
  end

  resources :orders, only: [:index, :create, :destroy]

  get '/saml/auth' => 'saml_idp#login'
  get '/saml/metadata' => 'saml_idp#metadata'
  post '/saml/auth' => 'saml_idp#auth'

  resources :print_orders, only: [:index, :create, :update, :new, :destroy] do
    get :invoice
  end

  resources :project_proposals do
    collection do
      post :approval
      post :disapproval
      get :join_project_proposal
      get :unjoin_project_proposal
      get :projects_assigned
      get :projects_completed
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
  namespace :static_pages, path: '/', as: nil do
    get 'forgot_password'
    get 'reset_password'
    get 'terms-of-service', as: 'tos'
    get 'hours'
    get 'about'
    get 'contact'
    get 'calendar'
    get 'report_repository', path: 'report_repository/:repository_id'
  end

  # RFID
  namespace :rfid do
    post 'card_number'
  end

  # SEARCH PAGES
  namespace :search, path: '/', as: nil do
    get 'explore'
    get 'search'
    get 'category', path: 'category/:slug'
    get 'featured', path: 'category/:slug/featured'
    get 'equipment', path: 'equipment/:slug'
  end

  # TEMPLATE
  namespace :template do
    get 'file'
    get 'category'
    get 'equipment'
    get 'certification'
    get 'comment'
  end

  # SESSION
  namespace :sessions, path: '/', as: nil do
    post 'login_authentication'
    get 'logout'
    get 'login'
  end

  # GITHUB
  namespace :github do
    get 'authorize'
    get 'callback'
    get 'unauthorize'
    get 'repositories'
  end

  # SETTING
  namespace :settings do
    get 'profile'
    get 'admin'
  end

  resources :skills, only: [:edit, :update]

  get 'help', to: 'help#main'
  put 'send_email', to:'help#send_email'

  namespace :licenses do
    get 'common-creative-attribution', as: 'cca'
    get 'common-creative-attribution-share-alike', as: 'ccasa'
    get 'common-creative-attribution-no-derivatives', as: 'ccand'
    get 'common-creative-attribution-non-commercial', as: 'ccanc'
    get 'attribution-non-commercial-share-alike', as: 'ancsa'
    get 'attribution-non-commercial-no-derivatives', as: 'ancnd'
  end

  namespace :getting_started, path: 'getting-started' do
    get 'setting-up-account', as: 'sua'
    get 'creating-repository', as: 'cr'
  end

  namespace :admin do
    get 'index', path: '/'

    get 'manage_badges'

    namespace :report_generator do
      get 'index', path: '/'
      post 'generate', path: '/generate', format: :xlsx
    end

    resources :users, only: [:index, :edit, :update, :show] do
      collection do
        get 'search'
        post 'bulk_add_certifications'
        patch 'set_role'
        delete 'delete_repository'
        delete 'delete_project_proposal'
        delete 'delete_user'
        get 'manage_roles'
      end
    end

    resources :spaces, only: [:index, :create, :edit] do
      delete 'destroy', path: '/edit/'
    end

    resources :pi_readers, only: [:update]

    resources :trainings

    resources :training_sessions do
      get 'index', path: '/'

      member do
        patch 'update'
      end
    end

    resources :settings, only: [:index] do
      collection do
        post 'add_category'
        post 'add_area'
        post 'add_printer'
        # post 'rename_category'
        post 'remove_category'
        post 'remove_area'
        post 'remove_printer'
        post 'add_equipment'
        post 'rename_equipment'
        post 'remove_equipment'
        post 'submit_pi'
        post 'remove_pi'
        get 'pin_unpin_repository'

      end
    end
  end


  namespace :staff do
    get 'index', path: '/'

    resources :training_sessions do
      get 'index', path: '/', on: :collection
      member do
        post 'certify_trainees'
        patch 'renew_certification'
        delete 'revoke_certification'
        get 'training_report'
      end
    end
  end

  namespace :staff_dashboard do
    get 'index', path: '/'
    get 'search'
    get 'present_users_report'
    put 'change_space', path: '/change_space'
    put 'sign_in_users', path: '/add_users'
    put 'sign_out_users', path: '/remove_users'
    put 'link_rfid'
    put 'unlink_rfid'
    get 'sign_out_all_users'
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
      get "grant_badge", path: "grant"
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
      get :open_modal
    end
  end

  resources :project_requirements, only: [:create, :destroy]

  resources :volunteers, only: [:index] do
    collection do
      get :emails
      get :volunteer_list
      get :getting_started
      get :join_volunteer_program
      get :my_stats
    end
  end

  resources :questions

  resources :exams, only: [:index, :create, :show, :destroy] do
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
    end
  end

  resources :announcements

  resources :volunteer_task_joins, only: [:create] do
    collection do
      post :remove
    end
  end

  resources :volunteer_requests, only: [:index, :create, :show] do
    collection do
      put :update_approval
    end
  end

  resources :volunteer_hours, only: [:index, :create, :new, :edit, :destroy, :update] do
    collection do
      get :volunteer_hour_requests
      put :update_approval
      get :volunteer_hour_per_user
    end
  end

  resources :require_trainings, only: [:create] do
    collection do
      post :remove_trainings
    end
  end

  # namespace :help do
  #   get 'main', path: '/'
  # end
  # get 'repositories', to: 'repositories#index'
  post 'vote', to: 'users#vote', path: 'vote/:comment_id'

   # USER RESOURCES
  resources :users, path: '/', param: :username, except: :edit do
    collection do
      post :create, path: '/new'
    end

    get 'likes', on: :member
    patch 'change_password', on: :member
  end

  # REPOSITORY RESOURCES
  resources :repositories, path: '/:user_username', param: :slug, except: :index do
    post 'add_like', on: :member
    collection do
      get 'download_files', path: ':slug/download_files'
      get 'download', path: ':slug/download'
      patch :link_to_pp
      patch :add_owner
      patch :remove_owner
    end
    member do
      get 'password_entry', path: '/password_entry'
      post 'pass_authenticate'
    end

  end

  namespace :makes, path: 'makes/:user_username/:slug' do
    post 'create'
    get 'new'
  end

  namespace :comments do
    post :create, path: '/:slug'
    delete :destroy, path: '/:id/destroy'
  end

end
