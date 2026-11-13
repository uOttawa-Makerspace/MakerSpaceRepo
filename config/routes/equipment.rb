# frozen_string_literal: true

# A proposal's address is "<id>-<title>". Old links use "<id>.<title>", so the id segment may
# contain a dot; the controller sends those to the current address.
# A trailing ".json" or ".js" is still read as the response format.
resources :project_proposals, constraints: { id: /[^\/]+(?<!\.json)(?<!\.js)/ } do
  collection do
    post :create_revision
    post :approve
    post :decline
    post :join_project_proposal
    delete :unjoin_project_proposal
    get :projects_assigned
    get :projects_completed
    get :user_projects
  end
  resource :semester, only: :destroy, module: :project_proposals
end

resources :printers, only: %i[index update] do
  collection do
    get :staff_printers
    get :staff_printers_updates
    get :printer_data
    get :last_user_assigned_to_printer
    patch :link_printer_to_user
    patch :send_print_failed_message_to_user
    post :add_printer
    post :remove_printer
  end
end

resources :printer_types, except: %i[show]
resources :printer_issues,
          only: %i[index show new create edit update destroy] do
  post :resolve, on: :member
  collection do
    patch :update_notification_email
  end
end

resources :lockers, except: %i[new edit] do
  collection do
    post :create_multiple
    # Update only
    put :price
    put :enabled
    patch :bulk_edit
  end
end

resources :locker_sizes, only: [:create, :update, :destroy]

resources :locker_rentals, except: %i[edit destroy] do
  member do
    patch :renew
    patch :toggle_contacted
  end

  # Staff resolve a held payment (refunded / dismissed)
  resources :locker_payments, only: :update

  collection do
    get :admin
    get :assign_locker
    get :expired
  end
end

resources :kiosk, only: %i[index show edit] do
  post :sign_email
end
