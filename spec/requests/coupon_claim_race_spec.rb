# frozen_string_literal: true

require "rails_helper"

# D-S33: two concurrent POST /discount_codes, on real second connections (see
# rfid_link_concurrency_spec for the pattern). Thread 1 pauses inside its claim, at the
# CC debit (CcMoney.make_new_payment), after it has picked its coupon. Thread 2 then runs
# its whole request; the main thread waits until thread 2 either finished or is blocked on a
# row lock, then lets thread 1 go on.
#
# Fixed (was WART D-S33): the claim was find unclaimed -> debit -> assign with no lock, so
# thread 2 completed a claim of the same coupon and thread 1 then debited too and overwrote
# the owner (two debits, one coupon), and a user's two claims could overdraw the wallet.
# Now CouponCode.claim! locks the user row then the coupon row in one transaction.
RSpec.describe "Coupon claim race (D-S33)", type: :request do
  self.use_transactional_tests = false

  let(:password) { "asa32A353#" }
  let!(:user_a) { create(:user, :regular_user) }
  let!(:user_b) { create(:user, :regular_user) }

  after do
    ids = [user_a.id, user_b.id]
    CcMoney.where(user_id: ids).delete_all
    CouponCode.where(dollar_cost: 5).delete_all
    User.unscoped.where(id: ids).delete_all
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

  def login_session(user)
    open_session.tap do |s|
      s.post login_authentication_path, params: { username_email: user.username, password: password }
      expect(s.response.location).to end_with(root_path)
    end
  end

  def claim(session)
    session.post discount_codes_path, params: { dollar_cost: 5 }
    session.response
  end

  # Runs session_one's claim, pausing it at the debit while session_two's claim runs.
  # first_fails: session_one's debit then fails (its transaction rolls back).
  def race(session_one, session_two, first_fails: false)
    first = nil
    paused = Queue.new
    resume = Queue.new
    allow(CcMoney).to receive(:make_new_payment).and_wrap_original do |original, *args|
      if Thread.current == first
        first = nil
        paused << true
        resume.pop
        raise ActiveRecord::RecordNotSaved, "simulated" if first_fails
      end
      original.call(*args)
    end

    one = in_thread do
      first = Thread.current
      claim(session_one)
    end
    paused.pop
    two = in_thread { claim(session_two) }
    deadline = Time.current + 5
    Thread.pass until blocked_backends.positive? || !two.alive? || Time.current > deadline
    @second_waited = two.alive? # still running at the deadline/lock check: it is waiting on a lock
    resume << true

    [one.value, two.value].tap { |results| expect(results.grep(StandardError)).to be_empty }
  end

  def debits(user)
    CcMoney.where(user_id: user.id).where("cc < 0").pluck(:cc)
  end

  it "two users racing for the last coupon: the first gets it, the second is neither charged nor assigned" do
    coupon = create(:coupon_code, :unclaimed, dollar_cost: 5, cc_cost: 40)
    credit_cc!(user_a, 100)
    credit_cc!(user_b, 100)
    session_a = login_session(user_a)
    session_b = login_session(user_b)

    response_a, response_b = race(session_a, session_b)

    expect(coupon.reload.user_id).to eq(user_a.id)
    expect(debits(user_a)).to eq([-40])
    expect(debits(user_b)).to be_empty
    expect(user_a.reload.wallet).to eq(60)
    expect(user_b.reload.wallet).to eq(100)

    expect(response_a.location).to end_with(discount_codes_path)
    expect(session_a.flash[:notice]).to eq("Discount Code created")
    expect(response_b.location).to end_with(new_discount_code_path)
    expect(session_b.flash[:alert]).to eq("This coupon is already claimed")
  end

  it "one user claiming the same last coupon twice at once pays once" do
    coupon = create(:coupon_code, :unclaimed, dollar_cost: 5, cc_cost: 40)
    credit_cc!(user_a, 100)
    session_one = login_session(user_a)
    session_two = login_session(user_a)

    race(session_one, session_two)

    expect(coupon.reload.user_id).to eq(user_a.id)
    expect(debits(user_a)).to eq([-40])
    expect(user_a.reload.wallet).to eq(60)

    expect(session_one.flash[:notice]).to eq("Discount Code created")
    expect(session_two.flash[:alert]).to eq("This coupon is already claimed")
  end

  it "one user's two concurrent claims cannot overdraw the wallet: the second is refused" do
    coupons = create_list(:coupon_code, 2, :unclaimed, dollar_cost: 5, cc_cost: 40)
    credit_cc!(user_a, 50)
    session_one = login_session(user_a)
    session_two = login_session(user_a)

    race(session_one, session_two)

    expect(CouponCode.where(id: coupons.map(&:id), user_id: user_a.id).count).to eq(1)
    expect(CouponCode.where(id: coupons.map(&:id)).unclaimed.count).to eq(1)
    expect(debits(user_a)).to eq([-40])
    expect(user_a.reload.wallet).to eq(10)

    expect(session_one.flash[:notice]).to eq("Discount Code created")
    expect(session_two.flash[:alert]).to eq("Not enough CC points")
  end

  it "two users, two coupons: the second waits for the first's coupon, then takes the next one" do
    coupons = create_list(:coupon_code, 2, :unclaimed, dollar_cost: 5, cc_cost: 40)
    credit_cc!(user_a, 100)
    credit_cc!(user_b, 100)
    session_a = login_session(user_a)
    session_b = login_session(user_b)

    race(session_a, session_b)

    expect(@second_waited).to be(true)
    expect(coupons.map { |c| c.reload.user_id }).to eq([user_a.id, user_b.id])
    expect(debits(user_a)).to eq([-40])
    expect(debits(user_b)).to eq([-40])

    expect(session_a.flash[:notice]).to eq("Discount Code created")
    expect(session_b.flash[:notice]).to eq("Discount Code created")
  end

  it "a claimant whose claim rolls back frees the coupon for the one waiting on it (no false 'already claimed')" do
    coupon = create(:coupon_code, :unclaimed, dollar_cost: 5, cc_cost: 40)
    credit_cc!(user_a, 100)
    credit_cc!(user_b, 100)
    session_a = login_session(user_a)
    session_b = login_session(user_b)

    race(session_a, session_b, first_fails: true)

    expect(@second_waited).to be(true)
    expect(coupon.reload.user_id).to eq(user_b.id)
    expect(debits(user_a)).to be_empty
    expect(debits(user_b)).to eq([-40])
    expect(user_a.reload.wallet).to eq(100)

    expect(session_a.flash[:alert]).to eq("Discount Code not created properly!")
    expect(session_b.flash[:notice]).to eq("Discount Code created")
  end

  it "a coupon row held elsewhere past the lock timeout: the claim gives up, changes nothing, 'not created properly'" do
    stub_const("CouponCode::CLAIM_LOCK_TIMEOUT", "200ms")
    coupon = create(:coupon_code, :unclaimed, dollar_cost: 5, cc_cost: 40)
    credit_cc!(user_a, 100)
    session_a = login_session(user_a)

    locked = Queue.new
    release = Queue.new
    holder = in_thread do
      CouponCode.transaction do
        CouponCode.lock(User::GUARD_LOCK_MODE).find(coupon.id)
        locked << true
        release.pop(timeout: 3) # without a lock timeout the claim would wait this long, then succeed
      end
    end
    locked.pop
    started = Time.current
    claim(session_a)
    waited = Time.current - started
    release << true
    expect(holder.value).not_to be_a(StandardError)

    expect(waited).to be < 2
    expect(coupon.reload.user_id).to be_nil
    expect(debits(user_a)).to be_empty
    expect(user_a.reload.wallet).to eq(100)
    expect(session_a.response.location).to end_with(discount_codes_path)
    expect(session_a.flash[:alert]).to eq("Discount Code not created properly!")
  end
end
