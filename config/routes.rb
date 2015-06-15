Rails.application.routes.draw do

  root "static_pages#home"

  # USER RESOURCES
  resources :users do
    resources :repositories do
      member do
        post 'add_like'
      end
    end
    member do
      patch 'change_password'
      get 'account_setting'
    end
  end

  # STATIC PAGES
  namespace :static_pages, path: '/', as: nil do
    get 'about'
    get 'contact'
    get 'search' 
  end

  namespace :template do
    get 'file'
    get 'tag'
  end

  # SESSION 
  namespace :sessions, path: '/', as: nil do
    post 'login_authentication'
    get 'logout'
    get 'login'
  end

  #DROPBOX
  namespace :github do
    get 'authorize'
    get 'callback'
    get 'unauthorize'
    get 'repositories'
  end
  
end
