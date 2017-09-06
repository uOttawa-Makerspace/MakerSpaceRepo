Rails.application.routes.draw do

  root "static_pages#home"

  # STATIC PAGES
  namespace :static_pages, path: '/', as: nil do
    get 'forgot_password'
    get 'reset_password'
    get 'terms-of-service', as: 'tos'
    get 'hours'
    get 'about'
    get 'contact'
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

    resources :report_generator, only: [:index] do
      collection do
        get 'new_users'
        get 'total_visits'
        get 'unique_visits'
        get 'faculty_frequency'
        get 'gender_frequency'
        get 'training'
        put 'select_date_range'
        get 'repository'
      end
    end

    resources :users, only: [:index, :edit, :update, :show] do
      collection do
        get 'search'
        post 'bulk_add_certifications'
        patch 'set_role'
        delete 'delete_repository'
      end
    end

    resources :spaces, only: [:index, :create, :edit] do
      delete 'destroy', path: '/edit/'
    end

    resources :trainings, only: [:index, :create, :update, :destroy] do
    end

    resources :pi_readers, only: [:update] do
    end

    resources :training_sessions do
      get 'index', path: '/'

      member do
        patch 'update'
      end
    end

    resources :settings, only: [:index] do
      collection do
        post 'add_category'
        post 'rename_category'
        post 'remove_category'
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
    put 'change_space', path: '/change_space'
    put 'sign_in_users', path: '/add_users'
    put 'sign_out_users', path: '/remove_users'
    put 'link_rfid'
    put 'unlink_rfid'
  end

  # namespace :help do
  #   get 'main', path: '/'
  # end
  # get 'repositories', to: 'repositories#index'
  post 'vote', to: 'users#vote', path: 'vote/:comment_id'

   # USER RESOURCES
  resources :users, path: '/', param: :username, except: :edit do
    get 'likes', on: :member
    patch 'change_password', on: :member
  end

  # REPOSITORY RESOURCES
  resources :repositories, path: '/:user_username', param: :slug, except: :index do
    post 'add_like', on: :member
    collection do
      get 'download_files', path: ':slug/download_files'
      get 'download', path: ':slug/download'
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
