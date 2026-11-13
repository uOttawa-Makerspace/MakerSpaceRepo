# frozen_string_literal: true

resources :discount_codes, only: %i[new index create]
resources :coupon_codes, only: %i[index create destroy edit update]

resources :custom_webhooks, only: [] do
  collection do
    post :orders_paid
    post :orders_fulfilled
  end
end

resources :videos, only: %i[index new create destroy]
resources :project_kits, only: %i[index new create destroy] do
  patch :mark_delivered
  collection { get :populate_kit_users }
end

resources :cc_moneys, only: [:index] do
  collection do
    post :redeem
    get :link_cc_to_user
  end
end

resources :carts, only: [:index]
resources :order_items, only: %i[create update destroy] do
  post :revoke
  get :order_item_modal
  get :approve_order_item_modal
  get :revoke_order_item_modal
end

resources :orders, only: %i[index create destroy]
