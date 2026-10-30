# frozen_string_literal: true

require "rails_helper"

# D-S42: every CC spend (cart checkout, coupon claim) goes through CcMoney.debit!, which takes the
# wallet lock (the user row) and re-reads the balance under it. Real second connections, same
# pattern as coupon_claim_race_spec: thread 1 pauses inside its checkout at the first item's
# price (OrderItem#total_price, read right before the debit), thread 2 runs its whole request,
# the main thread waits until thread 2 finished or is blocked on a lock, then thread 1 goes on.
RSpec.describe "CC wallet races (D-S42)", type: :request do
  self.use_transactional_tests = false

  let(:password) { "asa32A353#" }
  let!(:user) { create(:user, :regular_user) }
  let!(:project_one) { create(:proficient_project, cc: 40) }
  let!(:project_two) { create(:proficient_project, cc: 40) }

  after do
    order_ids = Order.where(user_id: user.id).pluck(:id)
    OrderItem.where(order_id: order_ids).delete_all
    CcMoney.where(user_id: user.id).delete_all
    ProjectKit.where(user_id: user.id).delete_all
    Order.where(id: order_ids).delete_all
    CouponCode.where(dollar_cost: 5).delete_all
    projects = [project_one, project_two]
    trainings = Training.where(id: projects.map(&:training_id))
    skill_ids = trainings.pluck(:skill_id)
    ProficientProject.where(id: projects.map(&:id)).delete_all
    trainings.delete_all
    Skill.where(id: skill_ids).delete_all
    User.unscoped.where(id: user.id).delete_all
  end

  def in_thread(&block)
    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection(&block)
    rescue StandardError => e
      e
    end
  end

  def blocked_backends
    ActiveRecord::Base.connection.select_value(
      "SELECT count(*) FROM pg_stat_activity WHERE wait_event_type = 'Lock' AND datname = current_database()"
    ).to_i
  end

  def login_session
    open_session.tap do |s|
      s.post login_authentication_path, params: { username_email: user.username, password: password }
      expect(s.response.location).to end_with(root_path)
    end
  end

  def in_progress_order(project)
    Order.create!(user: user).tap { |o| o.order_items.create!(proficient_project: project, quantity: 1) }
  end

  # session_one's request pauses at `pause_at` ([class, method, nth call by that thread]: by
  # default its first item's price, read right before the debit); second_request runs meanwhile.
  def race(session_one, second_request, pause_at: [OrderItem, :total_price, 1])
    first = nil
    calls = 0
    paused = Queue.new
    resume = Queue.new
    klass, method, nth = pause_at
    allow_any_instance_of(klass).to receive(method).and_wrap_original do |original, *args|
      if Thread.current == first && (calls += 1) == nth
        first = nil
        paused << true
        resume.pop
      end
      original.call(*args)
    end

    one = in_thread do
      first = Thread.current
      session_one.post orders_path
    end
    paused.pop
    two = in_thread { second_request.call }
    deadline = Time.current + 5
    Thread.pass until blocked_backends.positive? || !two.alive? || Time.current > deadline
    @second_waited = two.alive?
    resume << true
    [one.value, two.value].each { |v| expect(v).not_to be_a(StandardError) }
  end

  def debits
    CcMoney.where(user_id: user.id).where("cc < 0").pluck(:cc)
  end

  it "two checkouts of two carts cannot overdraw the wallet: the second is refused" do
    credit_cc!(user, 50)
    session_one = login_session
    session_one.post order_items_path, params: { order_item: { proficient_project_id: project_one.id, quantity: 1 } }
    cart_one = Order.find(session_one.session[:order_id])
    cart_two = in_progress_order(project_two) # the user's last in-progress order: session_two's cart
    session_two = login_session

    race(session_one, -> { session_two.post orders_path })

    expect(debits).to eq([-40])
    expect(user.reload.wallet).to eq(10)
    expect(cart_one.reload.order_status.name).to eq("Completed")
    expect(cart_two.reload.order_status.name).to eq("In progress")
    expect(cart_two.cc_moneys).to be_empty
    expect(session_two.flash[:alert]).to eq("Not enough Cc Points.")
    expect(@second_waited).to be(true)
  end

  it "the same cart submitted twice at once is completed and debited once" do
    credit_cc!(user, 100)
    cart = in_progress_order(project_one)
    session_one = login_session
    session_two = login_session

    # pause after the checkout loaded the cart, before it completes it: the 2nd Order#subtotal
    # call of the request (the 1st is the check_wallet before_action)
    race(session_one, -> { session_two.post orders_path }, pause_at: [Order, :subtotal, 2])

    expect(debits).to eq([-40])
    expect(cart.reload.order_status.name).to eq("Completed")
    expect(cart.cc_moneys.count).to eq(1)
    expect(user.reload.wallet).to eq(60)
    expect(@second_waited).to be(true)
  end

  it "a coupon claim racing a checkout cannot overdraw the wallet: the claim is refused" do
    credit_cc!(user, 50)
    cart = in_progress_order(project_one)
    coupon = create(:coupon_code, :unclaimed, dollar_cost: 5, cc_cost: 40)
    session_one = login_session
    session_two = login_session

    race(session_one, -> { session_two.post discount_codes_path, params: { dollar_cost: 5 } })

    expect(debits).to eq([-40])
    expect(user.reload.wallet).to eq(10)
    expect(cart.reload.order_status.name).to eq("Completed")
    expect(coupon.reload.user_id).to be_nil
    expect(session_two.flash[:alert]).to eq("Not enough CC points")
    expect(@second_waited).to be(true)
  end
end
