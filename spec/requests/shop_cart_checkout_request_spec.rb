# frozen_string_literal: true

require "rails_helper"

# Characterization of the proficient-project shop: cart (CartsController),
# order items (OrderItemsController) and checkout (OrdersController). Currency
# is "cc" points (no money moves); price rules / discount codes are NOT part of
# this flow (pinned below). Authentication is the custom session, driven with a
# real login POST. No external HTTP: nothing here reaches Shopify; a safety net
# makes any socket attempt raise.
RSpec.describe "Shop cart and checkout (HTTP contract)", type: :request do
  let(:user) { create(:user, :regular_user) }
  let(:other) { create(:user, :regular_user) }
  let(:staff) { create(:user, :staff) }
  let(:admin) { create(:user, :admin) }

  before do
    block_external_http!
    ActionMailer::Base.deliveries.clear
  end

  def pp_with_cc(cc, **attrs)
    create(:proficient_project, cc: cc, **attrs)
  end

  def add_to_cart(pp, quantity: 1)
    post order_items_path,
         params: { order_item: { proficient_project_id: pp.id, quantity: quantity } }
  end

  # ------------------------------------------------------------ auth gates

  describe "auth gates" do
    it "redirects guests to login?back_to=... without flash on every cart/order action" do
      pp = pp_with_cc(10)
      item = cart_for(user, 10).order_items.first

      get carts_path
      expect(response).to redirect_to(login_path(back_to: "/carts"))
      expect(flash[:alert]).to be_nil

      post order_items_path, params: { order_item: { proficient_project_id: pp.id, quantity: 1 } }
      expect(response).to redirect_to(login_path(back_to: "/order_items"))

      patch order_item_path(item), params: { order_item: { quantity: 2 } }
      expect(response).to redirect_to(login_path(back_to: "/order_items/#{item.id}"))

      get order_item_destroy_path(item)
      expect(response).to redirect_to(login_path(back_to: "/order_items/#{item.id}/revoke"))

      delete order_item_path(item)
      expect(response).to redirect_to(login_path(back_to: "/order_items/#{item.id}"))

      get orders_path
      expect(response).to redirect_to(login_path(back_to: "/orders"))

      post orders_path
      expect(response).to redirect_to(login_path(back_to: "/orders"))

      delete order_path(item.order)
      expect(response).to redirect_to(login_path(back_to: "/orders/#{item.order_id}"))
      expect(Order.exists?(item.order_id)).to be(true)

      %i[order_item_modal approve_order_item_modal revoke_order_item_modal].each do |modal|
        get public_send("order_item_#{modal}_path", item)
        expect(response).to have_http_status(:found)
        expect(response.location).to include("/login")
      end
    end
  end

  # ------------------------------------------------------------ cart view

  describe "GET /carts" do
    it "renders an empty cart for a user with no order" do
      shop_log_in!(user)
      get carts_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("cart")
      expect(user.orders.count).to eq(0)
    end

    # N+1 pinned: see defects.md D-PERF05, D-PERF06
    it "shows the items of the user's trailing in-progress order (no session order id)", skip_bullet: true do
      order = cart_for(user, 10, 20)
      shop_log_in!(user)
      get carts_path
      expect(response).to have_http_status(:ok)
      order.order_items.each do |oi|
        expect(response.body).to include(oi.proficient_project.title)
      end
    end

    it "ignores a trailing COMPLETED order and starts a fresh empty cart" do
      done = cart_for(user, 10)
      done.update!(order_status: order_status!("Completed"))
      shop_log_in!(user)
      get carts_path
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(done.order_items.first.proficient_project.title)
    end

    it "is open to staff and admin as well (no role gate)" do
      [staff, admin].each do |u|
        get logout_path
        shop_log_in!(u)
        get carts_path
        expect(response).to have_http_status(:ok)
      end
    end
  end

  # -------------------------------------------------------- add to cart

  describe "POST /order_items" do
    before { shop_log_in!(user) }

    it "creates the order and item, snapshots the unit price, redirects to the cart" do
      pp = pp_with_cc(25)
      expect { add_to_cart(pp, quantity: 2) }
        .to change(Order, :count).by(1).and change(OrderItem, :count).by(1)

      expect(response).to redirect_to(carts_path)
      expect(flash[:notice]).to eq("Successfully added item to cart")
      order = user.orders.last
      expect(order.order_status.name).to eq("In progress")
      expect(order.subtotal).to eq(50)
      item = order.order_items.first
      expect(item.unit_price).to eq(25)
      expect(item.total_price).to eq(50)
      expect(item.status).to eq("In progress")
    end

    it "reuses the same in-progress order for the next item" do
      add_to_cart(pp_with_cc(10))
      expect { add_to_cart(pp_with_cc(15)) }.not_to change(Order, :count)
      expect(user.orders.last.order_items.count).to eq(2)
      expect(user.orders.last.subtotal).to eq(25)
    end

    it "refuses a duplicate project: alert, no new row" do
      pp = pp_with_cc(10)
      add_to_cart(pp)
      expect { add_to_cart(pp) }.not_to change(OrderItem, :count)
      expect(response).to redirect_to(carts_path)
      expect(flash[:alert]).to eq("You have already ordered this item")
    end

    it "refuses when the user lacks the required training badges" do
      pp = pp_with_cc(10)
      create(:training_requirement, proficient_project: pp, training: create(:training), level: "Beginner")
      expect { add_to_cart(pp) }.not_to change(OrderItem, :count)
      expect(response).to redirect_to(carts_path)
      expect(flash[:alert]).to eq("You do not have the required badges to do this project")
    end

    it "does not persist an invalid quantity but STILL reports success" do
      pp = pp_with_cc(10)
      expect { add_to_cart(pp, quantity: 0) }.not_to change(OrderItem, :count)
      expect(response).to redirect_to(carts_path)
      # WART(D-S01): the invalid-quantity save is silently dropped yet the flash says it was added
      expect(flash[:notice]).to eq("Successfully added item to cart")
    end

    it "answers 404 for an unknown project" do
      add_to_cart(double(id: 999_999_999))
      expect(response).to have_http_status(:not_found)
    end

    it "answers 500 when the order_item param is missing entirely" do
      # WART(D-S06): params[:order_item][:proficient_project_id] is dereferenced unguarded, so a bad POST is a 500 (NoMethodError), not a 400
      post order_items_path, params: {}
      expect(response).to have_http_status(:internal_server_error)
      expect(OrderItem.count).to eq(0)
    end

    it "sets session[:order_id] so a later request keeps that cart" do
      add_to_cart(pp_with_cc(10))
      order = user.orders.last
      get carts_path
      expect(response.body).to include(order.order_items.first.proficient_project.title)
    end

    %i[staff admin].each do |role|
      it "lets #{role} shop identically" do
        get logout_path
        u = public_send(role)
        shop_log_in!(u)
        add_to_cart(pp_with_cc(5))
        expect(response).to redirect_to(carts_path)
        expect(u.orders.last.order_items.count).to eq(1)
      end
    end

    it "hands the previous user's cart to whoever logs in next on the same browser session" do
      add_to_cart(pp_with_cc(10))
      first_order = user.orders.last
      get logout_path
      shop_log_in!(staff)
      add_to_cart(pp_with_cc(5))
      # WART(D-S08): logout does not clear session[:order_id], so the next login adopts the previous user's cart and re-assigns the order to itself
      expect(first_order.reload.user_id).to eq(staff.id)
      expect(first_order.order_items.count).to eq(2)
      expect(user.orders.count).to eq(0)
    end
  end

  # ------------------------------------------------- update / remove item

  describe "PATCH /order_items/:id" do
    before { shop_log_in!(user) }

    it "re-totals the item when the quantity changes (xhr/js response)" do
      add_to_cart(pp_with_cc(10))
      item = user.orders.last.order_items.first
      patch order_item_path(item), params: { order_item: { quantity: 3 } }, xhr: true
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/javascript")
      expect(item.reload.quantity).to eq(3)
      expect(item.total_price).to eq(30)
      expect(item.unit_price).to eq(10)
      # the order's stored subtotal is only refreshed by Order#save, not by item updates
      expect(item.order.reload.subtotal).to eq(30)
    end

    it "keeps the old quantity when the new one is invalid" do
      add_to_cart(pp_with_cc(10))
      item = user.orders.last.order_items.first
      patch order_item_path(item), params: { order_item: { quantity: 0 } }, xhr: true
      expect(response).to have_http_status(:ok)
      expect(item.reload.quantity).to eq(1)
    end

    it "404s for an item that is not in the CURRENT cart (no cross-user edits)" do
      add_to_cart(pp_with_cc(10))
      foreign = cart_for(other, 10).order_items.first
      patch order_item_path(foreign), params: { order_item: { quantity: 9 } }, xhr: true
      expect(response).to have_http_status(:not_found)
      expect(foreign.reload.quantity).to eq(1)
    end

    it "answers 406 for a non-js request (only update.js.erb exists)" do
      add_to_cart(pp_with_cc(10))
      item = user.orders.last.order_items.first
      patch order_item_path(item), params: { order_item: { quantity: 2 } }
      expect(response).to have_http_status(:not_acceptable)
      expect(item.reload.quantity).to eq(2) # the write still happened
    end
  end

  describe "DELETE /order_items/:id and GET /order_items/:id/revoke" do
    before { shop_log_in!(user) }

    it "DELETE /order_items/:id (what the cart's remove button sends) 404s and removes nothing" do
      add_to_cart(pp_with_cc(10))
      item = user.orders.last.order_items.first
      # WART(D-S07): #destroy reads params[:order_item_id] but the cart button DELETEs /order_items/:id (params[:id]), so removing an item from the cart is broken
      expect { delete order_item_path(item) }.not_to change(OrderItem, :count)
      expect(response).to have_http_status(:not_found)
    end

    it "treats a GET on /revoke as a cart removal too (route points at #destroy)" do
      add_to_cart(pp_with_cc(10))
      item = user.orders.last.order_items.first
      # WART(D-S02): the badge-revoke route maps to order_items#destroy; OrderItemsController#revoke is unreachable and a bare GET deletes a cart row
      expect { get order_item_destroy_path(item) }.to change(OrderItem, :count).by(-1)
      expect(response).to redirect_to(carts_path)
      expect(flash[:notice]).to eq("Successfully removed item from cart")
    end

    it "404s when the item belongs to another user's order" do
      add_to_cart(pp_with_cc(10))
      foreign = cart_for(other, 10).order_items.first
      expect { delete order_item_path(foreign) }.not_to change(OrderItem, :count)
      expect(response).to have_http_status(:not_found)
    end

    it "OrderItemsController#revoke is not routable from any path" do
      expect(OrderItemsController.action_methods).to include("revoke")
      expect(Rails.application.routes.routes.map { |r| r.defaults.slice(:controller, :action) })
        .not_to include({ controller: "order_items", action: "revoke" })
    end
  end

  # -------------------------------------------------------------- modals

  describe "order item modals" do
    let(:item) { cart_for(other, 10).order_items.first }

    it "renders any order item's modal for ANY signed-in user (no ownership/role check)" do
      shop_log_in!(user)
      get order_item_order_item_modal_path(item)
      # WART(D-S03): modals expose another user's username, project and comments to any signed-in user (sequential ids)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(other.username)
      expect(response.body).to include("Order Item Information")
      expect(response.body).not_to include("<html")
    end

    it "renders the approve and revoke modals for any signed-in user too" do
      shop_log_in!(user)
      get order_item_approve_order_item_modal_path(item)
      expect(response).to have_http_status(:ok)
      get order_item_revoke_order_item_modal_path(item)
      expect(response).to have_http_status(:ok)
    end

    it "404s for an unknown item" do
      shop_log_in!(user)
      get order_item_order_item_modal_path(order_item_id: 999_999_999)
      expect(response).to have_http_status(:not_found)
    end
  end

  # ------------------------------------------------------------- checkout

  describe "POST /orders (checkout math)" do
    before { shop_log_in!(user) }

    # N+1 pinned: see defects.md D-PERF06
    it "debits the wallet: one negative cc_money per item, order Completed, total = subtotal", skip_bullet: true do
      credit_cc!(user, 100)
      add_to_cart(pp_with_cc(10), quantity: 2)
      add_to_cart(pp_with_cc(15))

      expect { post orders_path }.to change(Order, :count).by(0).and change(CcMoney, :count).by(2)

      expect(response).to redirect_to(orders_path)
      expect(flash[:notice]).to eq("Your Order was successfully processed.")
      order = user.orders.last
      expect(order.order_status.name).to eq("Completed")
      expect(order.subtotal).to eq(35)
      expect(order.total).to eq(35)
      expect(order.cc_moneys.order(:id).pluck(:cc)).to eq([-20, -15])
      expect(order.cc_moneys.pluck(:user_id).uniq).to eq([user.id])
      expect(order.cc_moneys.map(&:proficient_project_id).sort)
        .to eq(order.order_items.map(&:proficient_project_id).sort)
      expect(user.reload.wallet).to eq(65)
      expect(user.cc_moneys.sum(:cc)).to eq(65)
    end

    it "clears session[:order_id]: the next cart is empty and starts a new order" do
      credit_cc!(user, 50)
      add_to_cart(pp_with_cc(10))
      post orders_path
      get carts_path
      expect(response).to have_http_status(:ok)
      add_to_cart(pp_with_cc(5))
      expect(user.orders.count).to eq(2)
      expect(user.orders.order(:id).last.order_status.name).to eq("In progress")
    end

    it "allows an exact-balance purchase (wallet == subtotal)" do
      credit_cc!(user, 10)
      add_to_cart(pp_with_cc(10))
      post orders_path
      expect(flash[:notice]).to eq("Your Order was successfully processed.")
      expect(user.reload.wallet).to eq(0)
    end

    it "rejects when the wallet is short: alert, nothing debited, order stays in progress" do
      credit_cc!(user, 9)
      add_to_cart(pp_with_cc(10))
      expect { post orders_path }.not_to change(CcMoney, :count)
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq("Not enough Cc Points.")
      expect(user.orders.last.order_status.name).to eq("In progress")
    end

    it "refreshes the stored wallet from cc_moneys before comparing (stale column is ignored)" do
      CcMoney.create!(user: user, cc: 30)
      user.update_column(:wallet, 0)
      add_to_cart(pp_with_cc(10))
      post orders_path
      expect(flash[:notice]).to eq("Your Order was successfully processed.")
      expect(user.reload.wallet).to eq(20)
    end

    it "uses the price captured when the item was added, not the project's current price" do
      credit_cc!(user, 100)
      pp = pp_with_cc(10)
      add_to_cart(pp)
      pp.update!(cc: 90)
      post orders_path
      expect(user.orders.last.total).to eq(10)
      expect(user.reload.wallet).to eq(90)
    end

    it "is NOT affected by owned discount/coupon codes or price rules (they do not enter checkout math)" do
      credit_cc!(user, 100)
      create(:discount_code, user: user, price_rule: create(:price_rule, value: 5, cc: 50))
      create(:coupon_code, :claimed, user: user, dollar_cost: 5, cc_cost: 50)
      add_to_cart(pp_with_cc(40))
      post orders_path
      expect(user.orders.last.total).to eq(40)
      expect(user.reload.wallet).to eq(60)
    end

    it "checks out an empty cart: creates a Completed order of total 0 and no debit" do
      expect { post orders_path }.to change(Order, :count).by(1).and change(CcMoney, :count).by(0)
      expect(response).to redirect_to(orders_path)
      # WART(D-S04): an empty cart can be "purchased", creating a Completed zero-value order
      order = user.orders.last
      expect(order.order_status.name).to eq("Completed")
      expect(order.total).to eq(0)
      expect(order.order_items).to be_empty
    end

    it "free items (cc 0) record a 0 cc_money row" do
      add_to_cart(pp_with_cc(0))
      post orders_path
      expect(user.orders.last.cc_moneys.pluck(:cc)).to eq([0])
    end

    it "a kit project creates a ProjectKit and delivers the kit email" do
      credit_cc!(user, 50)
      pp = pp_with_cc(10, has_project_kit: true)
      add_to_cart(pp)
      ActionMailer::Base.deliveries.clear
      perform_enqueued_jobs { post orders_path }
      expect(ProjectKit.where(user_id: user.id, proficient_project_id: pp.id, delivered: false).count).to eq(1)
      expect(deliveries.size).to eq(1)
      expect(deliveries.first.to).to eq([user.email])
      expect(deliveries.first.subject).to eq("Your proficient project kit order")
    end

    it "no kit email for projects without a kit" do
      credit_cc!(user, 50)
      add_to_cart(pp_with_cc(10))
      ActionMailer::Base.deliveries.clear
      perform_enqueued_jobs { post orders_path }
      expect(deliveries).to be_empty
      expect(ProjectKit.count).to eq(0)
    end

    it "a second POST right after checkout checks out an empty cart (no double debit)" do
      credit_cc!(user, 50)
      add_to_cart(pp_with_cc(10))
      post orders_path
      expect { post orders_path }.to change(CcMoney, :count).by(0)
      expect(user.reload.wallet).to eq(40)
    end

    it "lets staff and admin check out the same way" do
      [staff, admin].each do |u|
        get logout_path
        shop_log_in!(u)
        credit_cc!(u, 20)
        add_to_cart(pp_with_cc(5))
        post orders_path
        expect(flash[:notice]).to eq("Your Order was successfully processed.")
        expect(u.reload.wallet).to eq(15)
      end
    end
  end

  # ------------------------------------------------------------- order list

  describe "GET /orders" do
    def completed_for(owner, cc = 10)
      o = cart_for(owner, cc)
      o.update!(order_status: order_status!("Completed"))
      o
    end

    it "lists only the user's COMPLETED orders (in-progress and other users' are excluded)" do
      mine = completed_for(user)
      pending = cart_for(user, 77)
      theirs = completed_for(other)
      shop_log_in!(user)
      get orders_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(mine.order_items.first.proficient_project.title)
      expect(response.body).not_to include(pending.order_items.first.proficient_project.title)
      expect(response.body).not_to include(theirs.order_items.first.proficient_project.title)
    end

    it "shows admins a second table with every order of every user and status" do
      pending = cart_for(other, 77)
      shop_log_in!(admin)
      get orders_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(pending.order_items.first.proficient_project.title)
    end

    it "does not show the all-orders table to staff" do
      pending = cart_for(other, 77)
      shop_log_in!(staff)
      get orders_path
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(pending.order_items.first.proficient_project.title)
    end
  end

  describe "DELETE /orders/:id" do
    let!(:order) do
      o = cart_for(other, 10)
      o.update!(order_status: order_status!("Completed"))
      CcMoney.create!(user: other, cc: -10, order: o)
      other.update_wallet
      o
    end

    it "is admin-only: regular users and staff get a flash alert and nothing is deleted" do
      [user, staff].each do |u|
        get logout_path
        shop_log_in!(u)
        expect { delete order_path(order) }.not_to change(Order, :count)
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq("You can't perform this action")
      end
    end

    it "lets an admin destroy anyone's order with its items and cc_moneys (points returned)" do
      shop_log_in!(admin)
      expect { delete order_path(order) }
        .to change(Order, :count).by(-1)
        .and change(OrderItem, :count).by(-1)
        .and change(CcMoney, :count).by(-1)
      expect(response).to redirect_to(orders_path)
      expect(flash[:notice]).to eq("The order was deleted and the CC points returned to the user.")
      expect(other.cc_moneys.sum(:cc)).to eq(0)
      # WART(D-S05): the cached users.wallet is not refreshed on refund, it stays debited until the next update_wallet
      expect(other.reload.wallet).to eq(-10)
    end

    it "404s for an unknown order id" do
      shop_log_in!(admin)
      delete order_path(999_999_999)
      expect(response).to have_http_status(:not_found)
    end
  end
end
