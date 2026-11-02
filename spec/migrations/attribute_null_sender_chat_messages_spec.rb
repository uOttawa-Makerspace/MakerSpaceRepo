require "rails_helper"
require Rails.root.join("db/migrate/20261025000001_attribute_null_sender_chat_messages_to_order_owner")

RSpec.describe AttributeNullSenderChatMessagesToOrderOwner, type: :request do
  let(:owner) { create(:user, :regular_user) }
  let(:staff_user) { create(:user, :staff) }
  before { seed_job_statuses! }

  let(:order) { make_job_order!(owner: owner, status_key: :staff_approval) }

  def raw_message(sender_id:, message: "hi", job_order_id: order.id)
    msg = ChatMessage.new(job_order_id: job_order_id, sender_id: sender_id, message: message)
    msg.save!(validate: false)
    msg
  end

  def migrate_up
    ActiveRecord::Migration.suppress_messages { described_class.new.up }
  end

  it "attributes NULL-sender rows to the order owner and leaves real senders alone" do
    orphan = raw_message(sender_id: nil, message: "from the void")
    real = raw_message(sender_id: staff_user.id, message: "staff reply")

    migrate_up

    expect(orphan.reload.sender_id).to eq(owner.id)
    expect(real.reload.sender_id).to eq(staff_user.id)
  end

  it "is idempotent" do
    orphan = raw_message(sender_id: nil)
    migrate_up
    expect { migrate_up }.not_to(change { orphan.reload.attributes })
  end

  it "skips rows whose order has no user" do
    ownerless = make_job_order!(owner: owner, status_key: :staff_approval)
    ownerless.update_columns(user_id: nil)
    orphan = raw_message(sender_id: nil, job_order_id: ownerless.id)

    migrate_up

    expect(orphan.reload.sender_id).to be_nil
  end

  it "has a no-op down" do
    orphan = raw_message(sender_id: nil)
    migrate_up
    expect { ActiveRecord::Migration.suppress_messages { described_class.new.down } }
      .not_to(change { orphan.reload.sender_id })
  end
end
