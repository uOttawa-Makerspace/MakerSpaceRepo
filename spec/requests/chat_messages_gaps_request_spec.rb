# frozen_string_literal: true

require "rails_helper"

# Chunk 11 gap-closer for ChatMessagesController: the notification recipient
# rules, rendering corners and HTML escaping, all by delivered
# mail outcome.

RSpec.describe "ChatMessages gaps", type: :request do
  let(:owner) { create(:user, :regular_user) }
  let(:staff) { create(:user, :staff) }
  let(:other_staff) { create(:user, :staff) }

  before do
    seed_job_statuses!
    ActionMailer::Base.deliveries.clear
  end

  def active_order!(status_key: :user_approval)
    make_job_order!(owner: owner, status_key: status_key).tap do |order|
      order.job_tasks.create!(title: "Task #1")
    end
  end

  def post_message(order, text)
    post chat_messages_path, params: { chat_message: { message: text, job_order_id: order.id } }
  end

  def deliveries
    ActionMailer::Base.deliveries
  end

  describe "notification recipients" do
    it "mails the owner when staff posts the first message of an order thread" do
      order = active_order!
      session_login!(staff)
      perform_enqueued_jobs { post_message(order, "Your quote is ready") }

      expect(order.chat_messages.pluck(:message)).to eq(["Your quote is ready"])
      expect(deliveries.map(&:to)).to eq([[owner.email]])
    end

    it "mails the assigned staff member when the customer writes first" do
      order = active_order!
      order.update!(assigned_staff: staff)
      session_login!(owner)
      perform_enqueued_jobs { post_message(order, "Hi, a question") }
      expect(deliveries.map(&:to)).to eq([[staff.email]])
    end

    it "mails the owner, the assigned staff and the earlier participants once each, never the author" do
      order = active_order!
      order.update!(assigned_staff: staff)
      travel_to(2.hours.ago) { ChatMessage.create!(job_order: order, sender: other_staff, message: "s1") }
      session_login!(other_staff)
      perform_enqueued_jobs { post_message(order, "again") }
      expect(deliveries.map(&:to)).to match_array([[owner.email], [staff.email]])

      deliveries.clear
      session_login!(staff)
      perform_enqueued_jobs { post_message(order, "from the assigned staff") }
      expect(deliveries.map(&:to)).to match_array([[owner.email], [other_staff.email]])
    end

    it "notifies every other earlier participant (distinct) once" do
      order = active_order!
      ChatMessage.create!(job_order: order, sender: owner, message: "o1")
      ChatMessage.create!(job_order: order, sender: owner, message: "o2")
      ChatMessage.create!(job_order: order, sender: other_staff, message: "s1")
      ActionMailer::Base.deliveries.clear
      session_login!(staff)
      perform_enqueued_jobs { post_message(order, "from staff") }

      expect(deliveries.map(&:to)).to match_array([[owner.email], [other_staff.email]])
      expect(deliveries.last.subject).to eq("MakerRepo - Nouveau message // New message")
    end

    # users 25 and 1607 are the default extra notification
    # recipients (Setting.chat_extra_recipients); where those ids exist they are mailed on
    # every thread, even if they never took part.
    it "always includes the users with the default extra recipients 25 and 1607" do
      hard_coded = [create(:user, :staff, id: 25), create(:user, :staff, id: 1607)]
      order = active_order!
      session_login!(owner)
      perform_enqueued_jobs { post_message(order, "Is anybody there?") }

      expect(deliveries.map(&:to)).to match_array(hard_coded.map { |user| [user.email] })
    end

    it "does not mail an earlier poster who is no longer staff, but still mails current staff and the owner" do
      order = active_order!
      travel_to(2.hours.ago) do
        ChatMessage.create!(job_order: order, sender: other_staff, message: "s1")
        ChatMessage.create!(job_order: order, sender: staff, message: "s2")
        ChatMessage.create!(job_order: order, sender: owner, message: "o1")
      end
      other_staff.update!(role: "regular_user")
      third = create(:user, :staff)
      session_login!(third)
      perform_enqueued_jobs { post_message(order, "new") }

      expect(deliveries.map(&:to)).to match_array([[owner.email], [staff.email]])
    end

    it "still notifies the others when an earlier poster has been soft-deleted" do
      order = active_order!
      gone = create(:user, :staff)
      travel_to(2.hours.ago) { ChatMessage.create!(job_order: order, sender: gone, message: "bye") }
      gone.update_columns(deleted: true)
      session_login!(staff)
      perform_enqueued_jobs { post_message(order, "hello") }

      expect(deliveries.map(&:to)).to eq([[owner.email]])
    end

    it "does not mail an assigned staff member who is no longer staff" do
      order = active_order!
      order.update!(assigned_staff: other_staff)
      other_staff.update!(role: "regular_user")
      session_login!(staff)
      perform_enqueued_jobs { post_message(order, "hello") }

      expect(deliveries.map(&:to)).to eq([[owner.email]])
    end

    it "mails the extra recipients saved in the setting instead of the default ones, ids and addresses alike" do
      listed = create(:user, :staff)
      Setting.set(Setting::CHAT_EXTRA_RECIPIENTS_KEY, "#{listed.id}, desk@example.com\n#{owner.email.upcase}")
      create(:user, :staff, id: 25)
      order = active_order!
      session_login!(staff)
      perform_enqueued_jobs { post_message(order, "Hello") }

      expect(deliveries.map(&:to)).to match_array([[owner.email], [listed.email], ["desk@example.com"]])
    end

    it "mails nobody extra when the setting is saved empty" do
      Setting.set(Setting::CHAT_EXTRA_RECIPIENTS_KEY, "")
      create(:user, :staff, id: 25)
      order = active_order!
      session_login!(owner)
      perform_enqueued_jobs { post_message(order, "Hello") }
      expect(deliveries).to be_empty
    end

    it "does not mail a participant whose account was deleted" do
      gone = create(:user, :staff)
      order = active_order!
      ChatMessage.create!(job_order: order, sender: gone, message: "before leaving")
      gone.soft_delete!
      ActionMailer::Base.deliveries.clear
      session_login!(owner)
      perform_enqueued_jobs { post_message(order, "Anyone there?") }

      expect(deliveries.flat_map(&:to)).not_to include(gone.email)
    end

    it "does not mail a hard-coded user about their own message" do
      author = create(:user, :staff, id: 25)
      other = create(:user, :staff, id: 1607)
      order = active_order!
      session_login!(author)
      perform_enqueued_jobs { post_message(order, "Posting as 25") }
      expect(deliveries.last.to).to eq([other.email])
    end
  end

  # `respond_to:` (typo for reply_to:) becomes a custom header and no Reply-To is set.
  describe "ChatMessageMailer headers" do
    it "has no reply-to, a respond_to header carrying the sender, and only the one recipient in To" do
      order = active_order!
      message = ChatMessage.create!(job_order: order, sender: staff, message: "hello")
      mail = ChatMessageMailer.new_message(message, owner.email)
      mail.deliver_now

      expect(mail.reply_to).to be_nil
      expect(mail.header["respond_to"].to_s).to eq(staff.email)
      expect(mail.to).to eq([owner.email])
    end
  end

  describe "rendering" do
    it "renders an empty thread as an empty 200 body" do
      order = active_order!
      session_login!(owner)
      get chat_messages_path(job_order_id: order.id)
      expect(response).to have_http_status(:ok)
      expect(response.body.strip).to eq("")
    end

    # the thread lookup is scoped to not_deleted
    it "404s the thread of a soft-deleted order" do
      order = active_order!
      ChatMessage.create!(job_order: order, sender: staff, message: "from the grave")
      order.update!(is_deleted: true)
      session_login!(owner)
      get chat_messages_path(job_order_id: order.id)
      expect(response).to have_http_status(:not_found)
    end

    # simple_format sanitizes (allow-list) rather than escapes: script tags are
    # stripped, harmless markup such as <b> passes through
    it "sanitizes HTML in a message in the thread (script stripped, <b> kept, & escaped)" do
      order = active_order!
      ChatMessage.create!(job_order: order, sender: owner, message: "<script>alert(1)</script> & <b>bold</b>")
      session_login!(owner)
      get chat_messages_path(job_order_id: order.id)
      expect(response.body).not_to include("<script>alert(1)</script>")
      expect(response.body).not_to include("<script>")
      expect(response.body).to include("&amp; <b>bold</b>")
    end

    it "escapes HTML in the notification mail body" do
      order = active_order!
      ChatMessage.create!(job_order: order, sender: owner, message: "first")
      session_login!(staff)
      perform_enqueued_jobs { post_message(order, "<img src=x onerror=alert(1)>") }

      body = deliveries.last.body.encoded
      expect(body).not_to include("<img src=x")
      expect(body).to include("&lt;img src=x onerror=alert(1)&gt;")
    end

    it "marks the signed-in sender's own messages as You and others with their name" do
      order = active_order!
      ChatMessage.create!(job_order: order, sender: staff, message: "from staff")
      session_login!(owner)
      get chat_messages_path(job_order_id: order.id)
      expect(response.body).to include(staff.name)
      expect(response.body).to include("(staff)")
      expect(response.body).not_to match(/You\s*\(staff\)/)
    end
  end
end
