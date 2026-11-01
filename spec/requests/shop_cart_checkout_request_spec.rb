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
      expect(response).to redirect_to(login_path)

      patch order_item_path(item), params: { order_item: { quantity: 2 } }
      expect(response).to redirect_to(login_path)

      post order_item_revoke_path(item)
      expect(response).to redirect_to(login_path)

      delete order_item_path(item)
      expect(response).to redirect_to(login_path)

      get orders_path
      expect(response).to redirect_to(login_path(back_to: "/orders"))

      post orders_path
      expect(response).to redirect_to(login_path)

      delete order_path(item.order)
      expect(response).to redirect_to(login_path)
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

    # N+1 pinned
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
      # the invalid-quantity save is silently dropped yet the flash says it was added
      expect(flash[:notice]).to eq("Successfully added item to cart")
    end

    it "answers 404 for an unknown project" do
      add_to_cart(double(id: 999_999_999))
      expect(response).to have_http_status(:not_found)
    end

    it "answers 500 when the order_item param is missing entirely" do
      # params[:order_item][:proficient_project_id] is dereferenced unguarded, so a bad POST is a 500 (NoMethodError), not a 400
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

    # sign_out clears session[:order_id] and current_order ignores a session order owned by someone else
    it "does not hand the previous user's cart to whoever logs in next on the same browser session" do
      add_to_cart(pp_with_cc(10))
      first_order = user.orders.last
      get logout_path
      shop_log_in!(staff)
      add_to_cart(pp_with_cc(5))
      expect(first_order.reload.user_id).to eq(user.id)
      expect(first_order.order_items.count).to eq(1)
      expect(staff.orders.last.order_items.count).to eq(1)
      expect(staff.orders.last).not_to eq(first_order)
    end

    it "shows an empty cart to the next user after logout" do
      add_to_cart(pp_with_cc(10))
      title = user.orders.last.order_items.first.proficient_project.title
      get logout_path
      shop_log_in!(staff)
      get carts_path
      expect(response.body).not_to include(title)
    end

    it "never adopts another user's order even when login happens without a logout" do
      add_to_cart(pp_with_cc(10))
      first_order = user.orders.last
      shop_log_in!(staff)
      add_to_cart(pp_with_cc(5))
      expect(first_order.reload.user_id).to eq(user.id)
      expect(first_order.order_items.count).to eq(1)
      expect(staff.orders.last.order_items.count).to eq(1)
    end

    # a session order is only the live cart while it is In progress and owned by current_user
    it "does not serve a Completed session order as the cart (no second checkout of it)" do
      credit_cc!(user, 100)
      add_to_cart(pp_with_cc(10))
      order = user.orders.last
      order.update!(order_status: order_status!("Completed"))
      expect { post orders_path }.not_to change { order.cc_moneys.count }
      expect(order.reload.order_items.count).to eq(1)
      expect(user.reload.wallet).to eq(100)
    end

    it "does not adopt a NULL-user (orphan) session order" do
      add_to_cart(pp_with_cc(10))
      order = user.orders.last
      title = order.order_items.first.proficient_project.title
      order.update_column(:user_id, nil)
      get carts_path
      expect(response.body).not_to include(title)
    end

    # a session order id that no longer resolves falls back to the user's own cart instead of a 404
    it "falls back to the user's cart when the session order was deleted" do
      add_to_cart(pp_with_cc(10))
      Order.where(user: user).destroy_all
      get carts_path
      expect(response).to have_http_status(:ok)
      add_to_cart(pp_with_cc(5))
      expect(user.orders.count).to eq(1)
      expect(user.orders.last.order_items.count).to eq(1)
    end

    it "keeps the same user's cart across requests" do
      add_to_cart(pp_with_cc(10))
      add_to_cart(pp_with_cc(5))
      expect(user.orders.count).to eq(1)
      expect(user.orders.last.order_items.count).to eq(2)
    end
  end

  # ------------------------------------------------- update / remove item

  # Order#change_items! (the cart-change lock). The threaded races of a cart change against a
  # real concurrent checkout are in spec/requests/cc_wallet_race_spec.rb.
  describe "cart changes refused by Order#change_items!" do
    before { shop_log_in!(user) }

    let(:closed_message) { "This cart was just checked out; it can no longer be changed." }
    let(:busy_message) { "Your cart is being updated elsewhere; please try again." }

    # The cart is checked out between the request loading it and the change taking the lock.
    def close_cart_before_the_lock
      completed = OrderStatus.find_by!(name: "Completed")
      allow_any_instance_of(Order).to receive(:change_items!).and_wrap_original do |m, *args, &block|
        m.receiver.update_column(:order_status_id, completed.id)
        m.call(*args, &block)
      end
    end

    def fail_the_lock_with(error_class)
      allow_any_instance_of(Order).to receive(:change_items!).and_raise(error_class)
    end

    let!(:item) do
      add_to_cart(pp_with_cc(10))
      user.orders.last.order_items.first
    end
    let(:order) { item.order }
    let(:other_project) { pp_with_cc(5) }

    def item_rows = OrderItem.where(order_id: order.id).pluck(:proficient_project_id, :quantity)

    it "create on a checked-out cart is refused: alert, nothing added" do
      close_cart_before_the_lock
      before = item_rows
      add_to_cart(other_project)
      expect(response).to redirect_to(carts_path)
      expect(flash[:alert]).to eq(closed_message)
      expect(item_rows).to eq(before)
      expect(OrderItem.where(proficient_project_id: other_project.id)).to be_empty
    end

    it "update on a checked-out cart is refused: 409 with a JS body showing the message and the real cart; quantity unchanged" do
      close_cart_before_the_lock
      patch order_item_path(item), params: { order_item: { quantity: 3 } }, xhr: true
      expect(response).to have_http_status(:conflict)
      expect(response.media_type).to eq("text/javascript")
      expect(response.body).to include(closed_message)
      expect(response.body).to include("shopping-cart")
      expect(item.reload.quantity).to eq(1)
    end

    it "the refused XHR update answers from the checked-out order itself: its items as paid, not an empty cart" do
      close_cart_before_the_lock
      patch order_item_path(item), params: { order_item: { quantity: 3 } }, xhr: true
      expect(response).to have_http_status(:conflict)
      expect(response.body).to include("This order was checked out with")
      expect(response.body).to include(ERB::Util.html_escape(item.proficient_project.title))
      expect(response.body).not_to include("There are no items in your shopping cart")
    end

    it "the checked-out answer never raises on a legacy row with a NULL unit_price or quantity" do
      close_cart_before_the_lock
      item.update_columns(unit_price: nil, quantity: nil, total_price: nil)
      patch order_item_path(item), params: { order_item: { quantity: 3 } }, xhr: true
      expect(response).to have_http_status(:conflict)
      expect(response.body).to include("This order was checked out with")
      expect(response.body).to include(ERB::Util.html_escape(item.proficient_project.title))
    end

    it "the checked-out answer shows the amounts stored at checkout, and the order's stored total" do
      close_cart_before_the_lock
      item.update_columns(quantity: 2, unit_price: 10, total_price: 20)
      order.update_columns(subtotal: 20)
      patch order_item_path(item), params: { order_item: { quantity: 3 } }, xhr: true
      expect(response.body).to include("&times; 2 (20 CC)")
      expect(response.body).to include("Total charged: 20 CC")
    end

    it "a refused XHR update leaves session[:order_id] as the success path does, and the badge is drawn from the order in hand" do
      patch order_item_path(item), params: { order_item: { quantity: 2 } }, xhr: true
      expect(response).to have_http_status(:ok)
      success_session_order = session[:order_id]
      expect(success_session_order).to eq(order.id)

      close_cart_before_the_lock
      patch order_item_path(item), params: { order_item: { quantity: 3 } }, xhr: true
      expect(response).to have_http_status(:conflict)
      expect(session[:order_id]).to eq(success_session_order)
      # checked out: no open cart, so the badge is 0 (not the count of a swapped-in cart)
      expect(response.body).to match(/cart-text.*fs-4\\?">0</)
    end

    it "a busy refusal keeps the cart's own badge count and session" do
      add_to_cart(other_project)
      fail_the_lock_with(ActiveRecord::LockWaitTimeout)
      patch order_item_path(item), params: { order_item: { quantity: 3 } }, xhr: true
      expect(response).to have_http_status(:conflict)
      expect(session[:order_id]).to eq(order.id)
      expect(response.body).to match(/cart-text.*fs-4\\?">2</)
    end

    it "the cart page prices through Order#priced_items (the one pricing), not its own copy" do
      expect_any_instance_of(Order).to receive(:priced_items).at_least(:once).and_call_original
      get carts_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Order Subtotal")
    end

    it "a refused non-XHR (HTML) update redirects to the cart with the alert; nothing changed" do
      close_cart_before_the_lock
      patch order_item_path(item), params: { order_item: { quantity: 3 } }
      expect(response).to redirect_to(carts_path)
      expect(flash[:alert]).to eq(closed_message)
      expect(item.reload.quantity).to eq(1)
    end

    it "a refused update in any other format answers a bare 409" do
      fail_the_lock_with(ActiveRecord::LockWaitTimeout)
      patch order_item_path(item, format: :json), params: { order_item: { quantity: 3 } }
      expect(response).to have_http_status(:conflict)
      expect(response.body).to be_blank
      expect(item.reload.quantity).to eq(1)
    end

    it "destroy on a checked-out cart is refused: alert, the item stays" do
      close_cart_before_the_lock
      delete order_item_path(item)
      expect(response).to redirect_to(carts_path)
      expect(flash[:alert]).to eq(closed_message)
      expect(OrderItem.exists?(item.id)).to be(true)
    end

    [ActiveRecord::LockWaitTimeout, ActiveRecord::Deadlocked].each do |error_class|
      it "a #{error_class.name.demodulize} on create, update and destroy is refused with the busy message (no 500), nothing written" do
        fail_the_lock_with(error_class)
        before = item_rows

        add_to_cart(other_project)
        expect(response).to redirect_to(carts_path)
        expect(flash[:alert]).to eq(busy_message)

        patch order_item_path(item), params: { order_item: { quantity: 3 } }, xhr: true
        expect(response).to have_http_status(:conflict)
        expect(response.body).to include(busy_message)

        delete order_item_path(item)
        expect(response).to redirect_to(carts_path)
        expect(flash[:alert]).to eq(busy_message)

        expect(item_rows).to eq(before)
      end
    end
  end

  describe "a cart change waiting on a lock held by a checkout (real second connection)" do
    self.use_transactional_tests = false

    let!(:buyer) { create(:user, :regular_user) }
    let!(:project) { create(:proficient_project, cc: 10) }
    let!(:other_project) { create(:proficient_project, cc: 5) }

    after do
      order_ids = Order.where(user_id: buyer.id).pluck(:id)
      OrderItem.where(order_id: order_ids).delete_all
      Order.where(id: order_ids).delete_all
      projects = [project, other_project]
      trainings = Training.where(id: projects.map(&:training_id))
      skill_ids = trainings.pluck(:skill_id)
      ProficientProject.where(id: projects.map(&:id)).delete_all
      trainings.delete_all
      Skill.where(id: skill_ids).delete_all
      User.unscoped.where(id: buyer.id).delete_all
    end

    it "gives up after the lock timeout with the busy message; nothing added" do
      stub_const("ApplicationRecord::LOCK_TIMEOUT", "200ms")
      shop_log_in!(buyer)
      add_to_cart(project)
      cart = buyer.orders.last
      locked = Queue.new
      release = Queue.new
      holder = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          Order.transaction do
            Order.lock(Order::CART_LOCK_MODE).find(cart.id) # as checkout! holds it
            locked << true
            release.pop(timeout: 3)
          end
        end
      end
      locked.pop
      started = Time.current
      add_to_cart(other_project)
      waited = Time.current - started
      release << true
      holder.join
      expect(waited).to be < 2
      expect(flash[:alert]).to eq("Your cart is being updated elsewhere; please try again.")
      expect(cart.order_items.pluck(:proficient_project_id)).to eq([project.id])
    end
  end

  describe "GET /carts with an item that can no longer be bought" do
    before { shop_log_in!(user) }

    it "shows the item as needing removal (not 0) and no total or Confirm button" do
      add_to_cart(pp_with_cc(10))
      add_to_cart(pp_with_cc(15))
      user.orders.last.order_items.last.update_column(:quantity, 0)
      get carts_path
      expect(response.body).to include("No longer available: please remove this item")
      expect(response.body).to include("Remove the items marked as no longer available to see your total and check out.")
      expect(response.body).not_to include("Confirm order")
    end

    it "shows the same total the checkout charges when every item is valid" do
      add_to_cart(pp_with_cc(10), quantity: 2)
      get carts_path
      expect(response.body).to include("Confirm order, the total is 20 CC")
    end
  end

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

    it "refuses to swap the item's project (pay less): the project, price and charge stay the cheap one's" do
      credit_cc!(user, 500)
      cheap = pp_with_cc(10)
      pricey = pp_with_cc(400)
      add_to_cart(cheap)
      item = user.orders.last.order_items.first
      patch order_item_path(item), params: { order_item: { proficient_project_id: pricey.id, quantity: 1 } }, xhr: true
      expect(item.reload.proficient_project_id).to eq(cheap.id)
      post orders_path
      order = user.orders.order(:id).last
      expect(order.order_items.pluck(:proficient_project_id)).to eq([cheap.id])
      expect(order.cc_moneys.pluck(:cc, :proficient_project_id)).to eq([[-10, cheap.id]])
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

  describe "DELETE /order_items/:id and POST /order_items/:order_item_id/revoke" do
    before { shop_log_in!(user) }

    # #destroy reads params[:id], which is what the cart's remove button DELETEs
    it "DELETE /order_items/:id (what the cart's remove button sends) removes the item from the cart" do
      add_to_cart(pp_with_cc(10))
      item = user.orders.last.order_items.first
      expect { delete order_item_path(item) }.to change(OrderItem, :count).by(-1)
      expect(response).to redirect_to(carts_path)
      expect(flash[:notice]).to eq("Successfully removed item from cart")
    end

    # the GET /order_items/:id/revoke alias of #destroy is gone; a bare GET changes nothing
    it "does not delete a cart row on GET /order_items/:id/revoke" do
      add_to_cart(pp_with_cc(10))
      item = user.orders.last.order_items.first
      expect { get "/order_items/#{item.id}/revoke" }.not_to change(OrderItem, :count)
      expect(response).not_to have_http_status(:ok)
      expect(OrderItem.exists?(item.id)).to be(true)
    end

    it "404s when the item belongs to another user's order" do
      add_to_cart(pp_with_cc(10))
      foreign = cart_for(other, 10).order_items.first
      expect { delete order_item_path(foreign) }.not_to change(OrderItem, :count)
      expect(response).to have_http_status(:not_found)
    end

    # OrderItemsController#revoke is routed (POST) and admin only
    it "routes POST /order_items/:order_item_id/revoke to #revoke" do
      expect(Rails.application.routes.routes.map { |r| r.defaults.slice(:controller, :action) })
        .to include({ controller: "order_items", action: "revoke" })
    end

    it "forbids a regular user and staff from revoking, changing nothing" do
      item = cart_for(other, 10).order_items.first
      [user, staff].each do |u|
        shop_log_in!(u)
        expect { post order_item_revoke_path(item) }.not_to(change { item.reload.status })
        expect(response).to have_http_status(:forbidden)
      end
    end

    it "lets an admin revoke the order item and redirects to the admin index" do
      item = cart_for(other, 10).order_items.first
      shop_log_in!(admin)
      post order_item_revoke_path(item)
      expect(response).to redirect_to(admin_index_path)
      expect(flash[:notice]).to eq("The badge has been revoked.")
      expect(item.reload.status).to eq("Revoked")
    end
  end

  # -------------------------------------------------------------- modals

  describe "order item modals" do
    let(:item) { cart_for(other, 10).order_items.first }

    # the three modals are staff/admin only (403 fragment for signed-in non-staff, including the item's owner); guests still go to login
    it "renders the info modal for staff and admin" do
      [staff, admin].each do |u|
        get logout_path
        shop_log_in!(u)
        get order_item_order_item_modal_path(item)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(other.username)
        expect(response.body).to include("Order Item Information")
        expect(response.body).not_to include("<html")
      end
    end

    it "renders the approve and revoke modals for staff and admin" do
      [staff, admin].each do |u|
        get logout_path
        shop_log_in!(u)
        get order_item_approve_order_item_modal_path(item)
        expect(response).to have_http_status(:ok)
        get order_item_revoke_order_item_modal_path(item)
        expect(response).to have_http_status(:ok)
      end
    end

    it "403s all three modals for a regular user who is not the owner, leaking nothing" do
      shop_log_in!(user)
      [order_item_order_item_modal_path(item),
       order_item_approve_order_item_modal_path(item),
       order_item_revoke_order_item_modal_path(item)].each do |path|
        get path
        expect(response).to have_http_status(:forbidden)
        expect(response.body).not_to include(other.username)
      end
    end

    it "403s the modals for the item's own owner too (staff tooling)" do
      shop_log_in!(other)
      get order_item_order_item_modal_path(item)
      expect(response).to have_http_status(:forbidden)
      get order_item_approve_order_item_modal_path(item)
      expect(response).to have_http_status(:forbidden)
    end

    it "sends guests to login" do
      get order_item_order_item_modal_path(item)
      expect(response).to have_http_status(:found)
      expect(response.location).to include("/login")
    end

    it "404s for an unknown item (staff)" do
      shop_log_in!(staff)
      get order_item_order_item_modal_path(order_item_id: 999_999_999)
      expect(response).to have_http_status(:not_found)
    end
  end

  # ------------------------------------------------------------- checkout

  describe "POST /orders (checkout math)" do
    before { shop_log_in!(user) }

    # N+1 pinned
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
      # one debit per item; insertion order follows unordered order_items, so compare as a set
      expect(order.cc_moneys.pluck(:cc).sort).to eq([-20, -15])
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

    it "is NOT affected by owned coupon codes (they do not enter checkout math)" do
      credit_cc!(user, 100)
      create(:coupon_code, :claimed, user: user, dollar_cost: 5, cc_cost: 50)
      add_to_cart(pp_with_cc(40))
      post orders_path
      expect(user.orders.last.total).to eq(40)
      expect(user.reload.wallet).to eq(60)
    end

    it "checks out an empty cart: creates a Completed order of total 0 and no debit" do
      expect { post orders_path }.to change(Order, :count).by(1).and change(CcMoney, :count).by(0)
      expect(response).to redirect_to(orders_path)
      # an empty cart can be "purchased", creating a Completed zero-value order
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

    it "sends the kit email after the checkout transaction commits" do
      credit_cc!(user, 50)
      add_to_cart(pp_with_cc(10, has_project_kit: true))
      baseline = ActiveRecord::Base.connection.open_transactions # the spec's fixture transaction
      seen = nil
      allow(MsrMailer).to receive(:send_kit_email).and_wrap_original do |original, *args|
        seen = ActiveRecord::Base.connection.open_transactions
        original.call(*args)
      end
      post orders_path
      expect(seen).to eq(baseline)
    end

    it "a kit email that fails after the commit keeps the paid order and is reported (no 500)" do
      credit_cc!(user, 50)
      pp = pp_with_cc(10, has_project_kit: true)
      add_to_cart(pp)
      allow(MsrMailer).to receive(:send_kit_email).and_raise(Net::SMTPFatalError.new("550 user@example.com"))
      allow(Rails.error).to receive(:report).and_call_original
      post orders_path
      expect(response).to redirect_to(orders_path)
      expect(flash[:notice]).to eq("Your Order was successfully processed.")
      expect(user.orders.last.order_status.name).to eq("Completed")
      expect(user.reload.wallet).to eq(40)
      expect(ProjectKit.where(user_id: user.id, proficient_project_id: pp.id).count).to eq(1)
      expect(Rails.error).to have_received(:report)
        .with(an_instance_of(Net::SMTPFatalError), hash_including(context: { user_id: user.id, proficient_project_id: pp.id }))
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

    it "an order neither in progress nor completed is an error: no success flash, nothing debited, cart session kept" do
      credit_cc!(user, 50)
      add_to_cart(pp_with_cc(10))
      order = user.orders.last
      allow(Order).to receive(:checkout!).and_wrap_original do |original, _order, payer|
        order.update_column(:order_status_id, OrderStatus.find_or_create_by!(name: "Cancelled").id)
        original.call(order.reload, payer)
      end
      post orders_path
      expect(flash[:alert]).to eq("Something went wrong")
      expect(flash[:notice]).not_to eq("Your Order was successfully processed.")
      expect(session[:order_id]).to eq(order.id)
      expect(CcMoney.where(order_id: order.id)).to be_empty
      expect(user.reload.wallet).to eq(50)
    end

    [ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved, ActiveRecord::RecordNotFound,
     ActiveRecord::LockWaitTimeout, ActiveRecord::Deadlocked].each do |error_class|
      it "a #{error_class.name.demodulize} from checkout answers 'Something went wrong', not a 500" do
        credit_cc!(user, 50)
        add_to_cart(pp_with_cc(10))
        allow(Order).to receive(:checkout!).and_raise(error_class)
        post orders_path
        expect(response).to have_http_status(:redirect)
        expect(flash[:alert]).to eq("Something went wrong")
        expect(user.orders.last.order_status.name).to eq("In progress")
      end
    end

    it "a legacy negative price snapshot in the cart rolls the checkout back: 'Something went wrong', nothing debited" do
      credit_cc!(user, 50)
      add_to_cart(pp_with_cc(10))
      add_to_cart(pp_with_cc(5))
      order = user.orders.last
      order.order_items.last.update_columns(unit_price: -5, total_price: -5)
      post orders_path
      expect(response).to have_http_status(:redirect)
      expect(flash[:alert]).to eq("Something went wrong")
      expect(order.reload.order_status.name).to eq("In progress")
      expect(CcMoney.where(order_id: order.id)).to be_empty
      expect(user.reload.wallet).to eq(50)
    end

    it "an item that can no longer be bought (fails validation) refuses the checkout with a message; nothing charged" do
      credit_cc!(user, 50)
      add_to_cart(pp_with_cc(10))
      add_to_cart(pp_with_cc(15))
      order = user.orders.last
      order.order_items.last.update_column(:quantity, 0) # invalid: the cart showed it at 0
      post orders_path
      expect(flash[:alert]).to eq("An item in your cart can no longer be bought; remove it and try again.")
      expect(order.reload.order_status.name).to eq("In progress")
      expect(CcMoney.where(order_id: order.id)).to be_empty
      expect(session[:order_id]).to eq(order.id)
    end

    it "checkout! refuses an invalid item under the lock too (even past the pre-check)" do
      credit_cc!(user, 50)
      add_to_cart(pp_with_cc(10))
      order = user.orders.last
      order.order_items.first.update_column(:quantity, 0)
      expect(Order.checkout!(order, user).first).to eq(:invalid_items)
      expect(order.reload.order_status.name).to eq("In progress")
      expect(CcMoney.where(order_id: order.id)).to be_empty
    end

    it "the pre-check and the charge use one total (Order#subtotal of the open cart = the sum of item charges)" do
      credit_cc!(user, 100)
      add_to_cart(pp_with_cc(10), quantity: 2)
      add_to_cart(pp_with_cc(15))
      order = user.orders.last
      expect(order.subtotal).to eq(35)
      post orders_path
      expect(order.reload.total).to eq(35)
      expect(order.cc_moneys.sum(:cc)).to eq(-35)
    end

    it "checkout! builds the priced lines once under the lock: one item load, one validation per item" do
      credit_cc!(user, 100)
      add_to_cart(pp_with_cc(10))
      add_to_cart(pp_with_cc(15))
      order = user.orders.last
      validations = 0
      allow_any_instance_of(OrderItem).to receive(:valid?).and_wrap_original do |m, *args|
        validations += 1
        m.call(*args)
      end
      sqls = []
      sub = ActiveSupport::Notifications.subscribe("sql.active_record") { |*, p| sqls << p[:sql] }
      expect(Order.checkout!(order, user).first).to eq(:completed)
      ActiveSupport::Notifications.unsubscribe(sub)
      expect(validations).to eq(2)
      expect(sqls.count { |q| q.start_with?('SELECT "order_items".*') }).to eq(1)
      expect(order.reload[:subtotal]).to eq(25)
      expect(order.total).to eq(25)
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

    it "a completed order shows what was charged even if an item is now invalid; no per-row queries" do
      credit_cc!(user, 500)
      paid = Array.new(3) do |i|
        o = cart_for(user, 10 + i)
        Order.checkout!(o, user)
        o
      end
      paid.first.order_items.first.update_column(:quantity, 0) # now invalid
      shop_log_in!(user)
      count_for = lambda do |orders_shown|
        Order.where(id: (paid - orders_shown).map(&:id)).update_all(user_id: other.id)
        sqls = []
        sub = ActiveSupport::Notifications.subscribe("sql.active_record") { |*, p| sqls << p[:sql] }
        get orders_path
        ActiveSupport::Notifications.unsubscribe(sub)
        Order.where(id: paid.map(&:id)).update_all(user_id: user.id)
        sqls.size
      end
      count_for.call(paid) # warm-up (first-request caches)
      one = count_for.call([paid.first])
      expect(response.body).to include("<td><p>10.0</p></td>")
      three = count_for.call(paid)
      expect(three).to eq(one)
      expect(response.body).to include("<td><p>10.0</p></td>")
      expect(response.body).to include("<td><p>12.0</p></td>")
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
      # the cached users.wallet is not refreshed on refund, it stays debited until the next update_wallet
      expect(other.reload.wallet).to eq(-10)
    end

    it "404s for an unknown order id" do
      shop_log_in!(admin)
      delete order_path(999_999_999)
      expect(response).to have_http_status(:not_found)
    end
  end
end
