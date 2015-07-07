Rails.application.routes.draw do

  root "static_pages#home"

  # STATIC PAGES
  namespace :static_pages, path: '/', as: nil do
    get 'about'
    get 'contact'
    get 'report_repository', path: 'report_repository/:repository_id' 
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
    get :profile
    get :admin
  end 

  get 'repositories', to: 'repositories#index'
  post 'vote', to: 'users#vote', path: 'vote/:comment_id'

   # USER RESOURCES
  resources :users, path: '/', param: :username, except: :edit do
    get 'likes', on: :member
    patch 'change_password', on: :member
  end

  # REPOSITORY RESOURCES
  resources :repositories, path: '/:user_username', param: :title, except: :index do
    post 'add_like', on: :member
  end

  namespace :makes, path: 'makes/:user_name/:title' do
    post 'create'
    get 'new'
  end

  namespace :comments do
    post :create, path: '/:title'
  end

end
