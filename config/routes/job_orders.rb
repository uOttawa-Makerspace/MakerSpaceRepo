# frozen_string_literal: true

resources :job_orders, only: %i[index show create new destroy] do
  get :timeline_modal
  get :invoice
  patch :quote
  patch :user_approval
  patch :start_processing
  patch :processed
  patch :paid
  patch :picked_up
  patch :resend_quote_email
  patch :comments
  patch :assign_staff
  collection do
    get :admin
    get :settings
    get :user_magic_approval
    get :pay
    get :landing
    patch :user_magic_approval_confirmation
    post "/new" => "job_orders#new"
    patch "/new" => "job_orders#new"
  end
  resources :job_tasks, path: "task", only: [:create, :destroy, :edit, :update] do
    post :update, on: :member
  end
end

resources :chat_messages, only: [:index, :create]
