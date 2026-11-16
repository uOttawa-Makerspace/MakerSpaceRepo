# frozen_string_literal: true

resources :memberships, only: [:index, :create] do
  collection do
    post :admin_create_membership
    get :your_memberships
  end
  member do
    patch :revoke
  end
end
