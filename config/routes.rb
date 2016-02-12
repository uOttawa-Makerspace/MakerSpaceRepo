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
  resources :rfid, only: [:new, :create, :destroy], param: :username do
    post 'card_number', on: :collection
    get  'new_card_number', on: :collection
  end

  # SEARCH PAGES
  namespace :search, path: '/', as: nil do
    get 'explore'
    get 'search'
    get 'platform'
  end

  # TEMPLATE
  namespace :template do
    get 'file'
    get 'tag'
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

    resources :users, only: [:index, :show] do
      post 'make_admin', on: :member
    end
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
  end

  namespace :makes, path: 'makes/:user_username/:slug' do
    post 'create'
    get 'new'
  end

  namespace :comments do
    post :create, path: '/:slug'
  end

end
