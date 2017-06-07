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

    resources :users, only: [:index, :edit, :update, :show] do
      collection do
        get 'search'
        post 'bulk_add_certifications'
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
        post 'add_training'
        patch 'rename_training'
      end
    end
  end

  namespace :staff_dashboard do
    get 'index', path: '/'
  end


  # namespace :help do
  #   get 'main', path: '/'
  # end
  # get 'repositories', to: 'repositories#index'
  post 'vote', to: 'users#vote', path: 'vote/:comment_id'

   # USER RESOURCES
  resources :users, path: '/', param: :username, except: :edit do
    get 'likes', on: :member
    match 'additional_info', on: :member, via: [:get, :patch]
    patch 'change_password', on: :member
  end

  # REPOSITORY RESOURCES
  resources :repositories, path: '/:user_username', param: :slug, except: :index do
    post 'add_like', on: :member
    collection do
      get 'download_files', path: ':slug/download_files'
      get 'download', path: ':slug/download'
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
