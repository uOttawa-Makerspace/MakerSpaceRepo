Rails.application.routes.draw do

  root "static_pages#home"

  # STATIC PAGES
  namespace :static_pages, path: '/', as: nil do
    get 'forgot_password'
    get 'reset_password'
    get 'terms-of-service', as: 'tos'
    get 'privacy'
    get 'about'
    get 'contact'
    get 'report_repository/:repository_id', :as => 'report_repository', :action => 'report_repository'
  end

  # RFID
  namespace :rfid do
    post 'card_number'
  end

  # SEARCH PAGES
  namespace :search, path: '/', as: nil do
    get 'explore'
    get 'search'
    get 'category/:slug', :as => 'category', :action => 'category'
    get 'equipment/:slug', :as => 'equipment', :action => 'equipment'
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
    get '/', :as => 'index', :action => 'index'

    resources :report_generator, only: [:index] do
      collection do
        get 'new_users'
        get 'total_visits'
        get 'unique_visits'
        get 'faculty_frequency'
        get 'gender_frequency'
      end
    end
    resources :users, only: [:index, :edit, :update, :show] do
      collection do
        get 'search'
        post 'bulk_add_certifications'
        patch 'set_role'
        patch 'renew_certification'
        delete 'delete_repository'
        delete 'revoke_certification'
      end
    end

    resources :trainings do
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

      end
    end
  end


  namespace :staff do
    get '/', :as => 'index', :action => 'index'

    resources :training_sessions do
      member do
        post 'certify_trainees'
      end
    end
  end

  namespace :staff_dashboard do
    get '/', :as => 'index', :action => 'index'
  end

  # namespace :help do
  #   get 'main', path: '/'
  # end
  # get 'repositories', to: 'repositories#index'
  post 'vote/:comment_id', :as => 'vote', :action => 'vote'

   # USER RESOURCES
  resources :users, path: '/', param: :username, except: :edit do
    get 'likes', on: :member
    patch 'change_password', on: :member
  end

  # REPOSITORY RESOURCES
  resources :repositories, path: '/:user_username', param: :slug, except: :index do
    post 'add_like', on: :member
    collection do
      get 'download_files', :path => ':slug/download_files'
      get 'download', :path => ':slug/download'
    end
  end

  namespace :makes, path: 'makes/:user_username/:slug' do
    post 'create'
    get 'new'
  end

  namespace :comments do
    post :create, path: '/:slug'
  end

end
