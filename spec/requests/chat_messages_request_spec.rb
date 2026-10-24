# frozen_string_literal: true

require "rails_helper"

# Characterization spec for ChatMessagesController (chunk 6 "JobOrders").
#
# Pins the CURRENT observable behavior so a later refactor can prove no change:
# * The controller defines NO before_actions of its own — neither the `signed_in`
#   gate nor any ownership/permission check runs. `index` renders any order's
#   chat thread to any visitor, including guests.
# * `create` returns an empty 204 no matter what: on success (`return if save`),
#   and even when the record is invalid (a flash is set but nothing renders).
# * The after_save notification hook (ChatMessage) skips
#   1) while the order is still Draft and
#   2) when the same sender already posted within the last hour,
#   and enqueues ChatMessageMailer.new_message for the OTHER participants plus
#   the hardcoded admin ids 25 and 1607 (absent in a bare test DB).
RSpec.describe "ChatMessages (HTTP contract)", type: :request do
  let(:owner) { create(:user, :regular_user) }
  let(:staff) { create(:user, :staff) }
  let(:other) { create(:user, :regular_user) }

  before { seed_job_statuses! }

  def active_order!(owner_user: owner, status_key: :user_approval)
    make_job_order!(owner: owner_user, status_key: status_key).tap do |order|
      order.job_tasks.create!(title: "Task #1")
    end
  end

  # ------------------------------------------------------------- GET index

  # WART: no signed_in gate, no before_action at all, and the
  # job_order_id lookup belongs to any caller.
  describe "GET /chat_messages (index)" do
    it "renders a job order's chat thread with NO sign-in (leak — wart)" do
      order = active_order!
      ChatMessage.create!(job_order: order, sender: staff, message: "Quote attached!")
      ChatMessage.create!(job_order: order, sender: owner, message: "Thanks!")

      get chat_messages_path(job_order_id: order.id)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Quote attached!")
      expect(response.body).to include("Thanks!")
      expect(response.body).to include(staff.name)
      expect(response.body).to include("(staff)")
    end

    it "renders any OTHER user's order threads to a random signed-in user (no ownership check)" do
      order = active_order!(owner_user: owner)
      ChatMessage.create!(job_order: order, sender: staff, message: "internal staff note")

      session_login!(other)
      get chat_messages_path(job_order_id: order.id)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("internal staff note")
    end

    it "orders newest first and names senders for the viewing session as \"You\"" do
      order = active_order!
      ChatMessage.create!(job_order: order, sender: staff, message: "earlier message")
      session_login!(owner)
      ChatMessage.create!(job_order: order, sender: owner, message: "later message")

      get chat_messages_path(job_order_id: order.id)
      body = response.body
      expect(body.index("later message")).to be < body.index("earlier message")
      # Forbidden oddity: the partial writes "You" and ":" in separate ERB
      # chunks, so the body splits them with whitespace.
      expect(body).to match(/You\s*:/)
    end

    it "500 (RecordNotFound → not found) for an unknown job_order_id" do
      get chat_messages_path(job_order_id: 999_999_999)
      expect(response).to have_http_status(:not_found)
    end

    it "500 (RecordNotFound → not found) when job_order_id is missing entirely" do
      get chat_messages_path
      expect(response).to have_http_status(:not_found)
    end
  end

  # ------------------------------------------------------------- POST create

  describe "POST /chat_messages (create)" do
    it "persists the message for the signed-in sender and answers an empty 204" do
      order = active_order!
      session_login!(owner)

      expect do
        post chat_messages_path, params: { chat_message: { message: "Hello staff!", job_order_id: order.id } }
      end.to change { ChatMessage.count }.by(1)

      message = ChatMessage.last
      expect(message.message).to eq("Hello staff!")
      expect(message.job_order).to eq(order)
      expect(message.sender).to eq(owner)
      expect(message.is_read).to be(false)

      expect(response).to have_http_status(:no_content)
      expect(response.body).to be_blank
    end

    # WART (discovered 2026-10): a guest's `sender = User.new` does NOT block the
    # save — the belongs_to is not validated as required, so the message row is
    # PERSISTED with sender_id NULL (no ghost user row is created). The action
    # then early-returns on the successful save: empty 204, no flash.
    it "persists GUEST messages with a NULL sender and answers an empty 204 (wart)" do
      order = active_order!

      users_before = User.count
      expect do
        post chat_messages_path,
             params: { chat_message: { message: "message from the void", job_order_id: order.id } }
      end.to change { ChatMessage.count }.by(1)

      expect(response).to have_http_status(:no_content)
      expect(response.body).to be_blank
      message = ChatMessage.last
      expect(message.message).to eq("message from the void")
      expect(message.reload.sender_id).to be_nil
      expect(User.count).to eq(users_before)
      expect(flash[:error]).to be_nil
    end

    it "204s with a failure flash for an empty message body" do
      order = active_order!
      session_login!(owner)

      expect do
        post chat_messages_path, params: { chat_message: { message: "", job_order_id: order.id } }
      end.not_to change { ChatMessage.count }

      expect(response).to have_http_status(:no_content)
      expect(response.body).to be_blank
      expect(flash[:error]).to start_with("Failed to send message")
    end

    # Missing chat_message param is rescued application-wide:
    # redirect to root with the raw exception message (same as JobOrders#create).
    it "redirects to root with the raw parameter_missing message when the params key is absent" do
      session_login!(owner)
      post chat_messages_path, params: { other: "x" }
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to include("param is missing or the value is empty")
    end

    it "enqueues the notification mail when a participant posts on a past-draft order" do
      order = active_order!
      # The owner's existing message establishes a participant; the hardcoded
      # admin ids (25, 1607) have no rows in the test DB, so the mail goes only
      # to the actual participants.
      ChatMessage.create!(job_order: order, sender: owner, message: "owner starts the thread")
      session_login!(staff)

      expect do
        post chat_messages_path, params: { chat_message: { message: "Quoting now!", job_order_id: order.id } }
      end.to have_enqueued_mail(ChatMessageMailer, :new_message)
    end

    it "does NOT enqueue any mail while the order is still a Draft" do
      order = active_order!(status_key: :draft)
      ChatMessage.create!(job_order: order, sender: owner, message: "draft chatter")
      session_login!(staff)

      expect do
        post chat_messages_path, params: { chat_message: { message: "too early", job_order_id: order.id } }
      end.not_to have_enqueued_mail(ChatMessageMailer, :new_message)
    end

    # The "recent message by the same sender in the last hour" throttle:
    # only the first notification of a burst is enqueued.
    it "throttles repeated messages from the same sender within an hour to one mail" do
      order = active_order!
      ChatMessage.create!(job_order: order, sender: owner, message: "owner starts the thread")
      session_login!(staff)

      expect do
        post chat_messages_path, params: { chat_message: { message: "first", job_order_id: order.id } }
      end.to have_enqueued_mail(ChatMessageMailer, :new_message)

      expect do
        post chat_messages_path, params: { chat_message: { message: "second", job_order_id: order.id } }
      end.not_to have_enqueued_mail(ChatMessageMailer, :new_message)
    end

    it "stops throttling after the hour passes (time-bound, not one-time)" do
      order = active_order!
      ChatMessage.create!(job_order: order, sender: owner, message: "owner starts the thread")
      session_login!(staff)

      ChatMessage.create!(job_order: order, sender: staff, message: "first burst message")
      travel 2.hours do
        expect do
          post chat_messages_path, params: { chat_message: { message: "after the hour", job_order_id: order.id } }
        end.to have_enqueued_mail(ChatMessageMailer, :new_message)
      end
    end
  end
end
