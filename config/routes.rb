# frozen_string_literal: true

Rails.application.routes.draw do
  mount MissionControl::Jobs::Engine, at: "/solid_queue"

  # Error pages: config.exceptions_app (config/application.rb) answers failed requests here.
  ErrorsController::PAGES.each_key do |code|
    match "/#{code}", to: "errors#show", via: :all, defaults: { code: code }, as: "error_page_#{code}"
  end

  if Rails.env.development?
    mount LetterOpenerWeb::Engine, at: "/letter_opener"
  end

  draw(:api)
  draw(:shop)
  draw(:saml)
  draw(:job_orders)
  draw(:equipment)
  draw(:memberships)
  draw(:site)
  draw(:admin)
  draw(:staff)
  draw(:learning)
  draw(:volunteers)
  draw(:exams)
  draw(:volunteer_work)

  # namespace :help do
  #   get 'main', path: '/'
  # end
  # get 'repositories', to: 'repositories#index'

  # NOTE: Routes are executed in order, any root route below this line is now a
  # request to a user page

  # USER RESOURCES
  resources :users, path: "/", param: :username, except: %i[index edit destroy] do
    collection do
      get :resend_confirmation
      post :resend_confirmation, action: :send_confirmation
      # the emailed link (GET) only shows a confirmation page; the
      # change is applied by its POST, and requesting one needs a POST with
      # the current password.
      get :confirm_edited_email
      post :confirm_edited_email, action: :apply_edited_email
      get :reset_password_form
      patch :reset_password_confirmation
      get :confirm
      post :confirm, action: :apply_confirmation
      match :change_programs, via: %i[post patch]
      post :create, path: "/new"
      delete :remove_avatar
      post :flag
      post :unflag
      post :change_email
      put :remove_flag
      get :unlock_account
      post :unlock_account, action: :apply_unlock
      get :search, path: "/users/search"
    end

    get "likes", on: :member
    resource :membership_check, only: :create, path: "membership_check"
    patch "change_password", on: :member
  end

  # Must come before the /:user_username catch-all below
  get "/repositories/populate_users", to: "repositories#populate_users"

  # REPOSITORY RESOURCES
  # /:user_username/:id
  # The repository is found by id, slug or title alone, because usernames can change and old links must not break.
  # RepositoriesController redirects a link with another username to the owner's current address.
  resources :repositories,
            path: '/:user_username',
            param: :id,
            except: :index do
    post 'add_like', on: :member
    collection do
      get ':id/download_files',
          as: 'download_files',
          action: 'download_files',
          constraints: {
            id: %r{[^/]+}
          }
      patch :link_to_pp
      patch :add_member
      patch :remove_member
      patch :transfer_owner
    end
    member do
      get '/password_entry', as: 'password_entry', action: 'password_entry'
      post 'pass_authenticate'
    end
  end

  namespace :makes, path: "makes/:user_username/:id" do
    post "create"
    get "new"
  end

  namespace :comments do
    post :create, path: "/:id"
    delete :destroy, path: "/:id/destroy"
    post :vote, path: "/:id/vote"
  end

  namespace :quick_access_links do
    post :create
    post :update, path: "update/:id", as: "update"
    delete :delete, path: "delete/:id", as: "delete"
  end
end
