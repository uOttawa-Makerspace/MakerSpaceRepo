# frozen_string_literal: true

require "rails_helper"

# Real second connections (see cc_wallet_race_spec). Thread 1 pauses right after reading the
# printer's last session; thread 2 then runs its whole request. Without a lock around the read,
# close and open, both requests close the same old session and each leaves its own new session
# in use. With the printer locked, the second request waits and then sees the first one's session.
RSpec.describe "Linking one printer to two users at once", type: :request do
  self.use_transactional_tests = false

  let(:password) { "asa32A353#" }
  let!(:staff) { create(:user, :staff) }
  let!(:first_user) { create(:user, :regular_user) }
  let!(:second_user) { create(:user, :regular_user) }
  let!(:printer) { create(:printer, :UM2P_01) }

  after do
    PrinterSession.where(printer_id: printer.id).delete_all
    printer_type_id = printer.printer_type_id
    Printer.unscoped.where(id: printer.id).delete_all
    PrinterType.where(id: printer_type_id).delete_all
    User.unscoped.where(id: [staff.id, first_user.id, second_user.id]).delete_all
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
      s.post login_authentication_path, params: { username_email: staff.username, password: password }
      expect(s.response.location).to end_with(root_path)
    end
  end

  def link(session, user)
    session.patch link_printer_to_user_printers_path(format: :json),
                  params: { printer: { printer_id: printer.id, user_id: user.id } }
  end

  it "leaves exactly one session in use, belonging to the request that ran last" do
    PrinterSession.create!(printer_id: printer.id, user_id: staff.id, in_use: true)
    session_one = login_session
    session_two = login_session
    first = nil
    paused = Queue.new
    resume = Queue.new
    allow(Printer).to receive(:get_last_number_session).and_wrap_original do |original, *args|
      last = original.call(*args)
      if Thread.current == first
        first = nil
        paused << true
        resume.pop(timeout: ThreadPause::PARKED_TIMEOUT)
      end
      last
    end

    one = in_thread do
      first = Thread.current
      link(session_one, first_user)
    end
    ThreadPause.await(paused)
    two = in_thread { link(session_two, second_user) }
    deadline = Time.current + 5
    Thread.pass until blocked_backends.positive? || !two.alive? || Time.current > deadline
    resume << true

    expect([one.value, two.value].grep(StandardError)).to be_empty
    sessions = PrinterSession.where(printer_id: printer.id).order(:id)
    expect(sessions.count).to eq(3)
    expect(sessions.where(in_use: true).count).to eq(1)
    expect(sessions.last).to have_attributes(user_id: second_user.id, in_use: true)
  end
end
