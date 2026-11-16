# frozen_string_literal: true

require "rails_helper"

# Real second connections, deterministic interleaving (see training_session_certify_concurrency_spec).
RSpec.describe TrainingSession, "#update_roster under concurrency", type: :model do
  self.use_transactional_tests = false

  let!(:trainer) { create(:user, :admin) }
  let!(:space) { create(:space) }
  let!(:training) { create(:training) }
  let!(:trainee) { create(:user) }
  let!(:newcomer) { create(:user) }
  let!(:session) do
    create(:training_session, user: trainer, space: space, training: training, level: "Beginner", users: [trainee])
  end

  after do
    Certification.unscoped.where(user_id: [trainee.id, newcomer.id]).delete_all
    session.users.clear
    TrainingSession.unscoped.where(id: session.id).delete_all
    [training, space].each { |r| r.class.unscoped.where(id: r.id).delete_all }
    Skill.where(id: training.skill_id).delete_all
    User.unscoped.where(id: [trainee.id, newcomer.id, trainer.id]).delete_all
  end

  def blocked_backends
    ActiveRecord::Base.connection.select_value(
      "SELECT count(*) FROM pg_stat_activity WHERE wait_event_type = 'Lock' AND datname = current_database()"
    ).to_i
  end

  # Thread 1 certifies and pauses before it commits. Thread 2 edits the level and the roster of the same
  # session: with the row lock it waits, then finds the session locked and writes nothing; without it,
  # it would see an editable session, change the level and the roster, and thread 1 would certify at
  # the old level.
  it "an edit that races a certification is refused and leaves the roster unchanged" do
    first = nil
    paused = Queue.new
    resume = Queue.new
    allow(Certification).to receive(:held_by).and_wrap_original do |original, *args|
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
        TrainingSession.find(session.id).certify_trainees!
      end
      ThreadPause.await(paused, "the certification")
      two = in_thread do
        TrainingSession.find(session.id).update_roster(
          { "level" => "Advanced" }, added: [newcomer.username], dropped: [trainee.username], by: trainer
        )
      end
      deadline = Time.current + 5
      Thread.pass until blocked_backends.positive? || !two.alive? || Time.current > deadline
    ensure
      resume << true
      [one, two].compact.each { |t| t.join(ThreadPause::AWAIT_TIMEOUT) }
    end

    expect([one.value, two.value].grep(StandardError)).to be_empty
    expect(two.value).not_to be_saved
    reloaded = TrainingSession.find(session.id)
    expect(reloaded.level).to eq("Beginner")
    expect(reloaded.users).to eq([trainee])
    expect(Certification.where(user_id: trainee.id).pluck(:level)).to eq(["Beginner"])
  end
end
