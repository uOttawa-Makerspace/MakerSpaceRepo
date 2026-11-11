# frozen_string_literal: true

require "rails_helper"

# Real second connections, deterministic interleaving (see training_session_certify_concurrency_spec).
RSpec.describe OrderItem, "#revoke under concurrency", type: :model do
  self.use_transactional_tests = false

  let!(:completed_status_existed) { OrderStatus.exists?(name: "Completed") }
  let!(:staff) { create(:user, :admin) }
  let!(:buyer) { create(:user) }
  let!(:project) { create(:proficient_project) }
  let!(:items) do
    Array.new(2) do
      create(:order_item, order: create(:order, :completed, user_id: buyer.id), proficient_project: project,
                          status: "Waiting for approval")
    end
  end

  before { items.each { |i| i.award!(staff) } }

  after do
    ProficientProjectSession.where(proficient_project_id: project.id).delete_all
    Certification.unscoped.where(user_id: buyer.id).delete_all
    orders = items.map(&:order_id)
    OrderItem.where(order_id: orders).delete_all
    Order.where(id: orders).delete_all
    OrderStatus.where(name: "Completed").delete_all unless completed_status_existed
    training = project.training
    ProficientProject.where(id: project.id).delete_all
    Training.where(id: training.id).delete_all
    Skill.where(id: training.skill_id).delete_all
    User.unscoped.where(id: [buyer.id, staff.id]).delete_all
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

  # Thread 1 pauses after learning that the sibling is still awarded. Thread 2 then revokes the
  # sibling: with the per-user-and-project lock it waits for thread 1; without it, it also sees the
  # first item as awarded, and both skip the deactivation, leaving the badge active.
  it "two admins revoking sibling items at once still deactivate the badge" do
    first = nil
    paused = Queue.new
    resume = Queue.new
    allow(OrderItem).to receive(:awarded).and_wrap_original do |original, *args|
      original.call(*args).tap do |relation|
        relation.define_singleton_method(:exists?) do |*a|
          super(*a).tap do
            if Thread.current == first
              first = nil
              paused << true
              resume.pop(timeout: ThreadPause::PARKED_TIMEOUT)
            end
          end
        end
      end
    end

    one = two = nil
    begin
      one = in_thread do
        first = Thread.current
        OrderItem.find(items[0].id).revoke(staff)
      end
      ThreadPause.await(paused, "the first revoke")
      two = in_thread { OrderItem.find(items[1].id).revoke(staff) }
      deadline = Time.current + 5
      Thread.pass until blocked_backends.positive? || !two.alive? || Time.current > deadline
    ensure
      resume << true
      [one, two].compact.each { |t| t.join(ThreadPause::AWAIT_TIMEOUT) }
    end

    expect([one.value, two.value]).to eq([true, true])
    expect(OrderItem.where(id: items.map(&:id)).pluck(:status)).to all(eq("Revoked"))
    expect(Certification.where(user_id: buyer.id)).to be_empty
  end
end
