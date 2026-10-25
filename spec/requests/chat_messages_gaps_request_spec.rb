# frozen_string_literal: true

require "rails_helper"

# Chunk 11 gap-closer for ChatMessagesController: the notification recipient
# rules (D-J28, D-J29), rendering corners and HTML escaping, all by delivered
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
    # WART(D-J28): recipients are only the OTHER users who already posted on the
    # order (plus hard-coded ids). Staff writing FIRST reaches nobody, so the
    # customer is never told about the first staff message.
    it "delivers nothing when staff posts the first message of an order thread" do
      order = active_order!
      session_login!(staff)
      perform_enqueued_jobs { post_message(order, "Your quote is ready") }

      expect(order.chat_messages.pluck(:message)).to eq(["Your quote is ready"])
      expect(deliveries).to be_empty
    end

    it "does not notify the assigned staff member when the customer writes first" do
      order = active_order!
      order.update!(assigned_staff: staff)
      session_login!(owner)
      perform_enqueued_jobs { post_message(order, "Hi, a question") }
      expect(deliveries).to be_empty
    end

    it "notifies every other earlier participant (distinct) once" do
      order = active_order!
      ChatMessage.create!(job_order: order, sender: owner, message: "o1")
      ChatMessage.create!(job_order: order, sender: owner, message: "o2")
      ChatMessage.create!(job_order: order, sender: other_staff, message: "s1")
      ActionMailer::Base.deliveries.clear
      session_login!(staff)
      perform_enqueued_jobs { post_message(order, "from staff") }

      expect(deliveries.size).to eq(1)
      expect(deliveries.last.to).to match_array([owner.email, other_staff.email])
      expect(deliveries.last.subject).to eq("MakerRepo - Nouveau message // New message")
    end

    # WART(D-J29): the user ids 25 and 1607 are hard-coded notification
    # recipients; in any environment where those ids exist they are mailed on
    # every thread, even if they never took part.
    it "always includes the users with the hard-coded ids 25 and 1607" do
      hard_coded = [create(:user, :staff, id: 25), create(:user, :staff, id: 1607)]
      order = active_order!
      session_login!(owner)
      perform_enqueued_jobs { post_message(order, "Is anybody there?") }

      expect(deliveries.size).to eq(1)
      expect(deliveries.last.to).to match_array(hard_coded.map(&:email))
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

  # WART(D-J43): `respond_to:` (typo for reply_to:) becomes a custom header, no
  # Reply-To is set, and every recipient is exposed in one To line.
  describe "ChatMessageMailer headers" do
    it "has no reply-to, a respond_to header carrying the sender and all recipients in To" do
      order = active_order!
      message = ChatMessage.create!(job_order: order, sender: staff, message: "hello")
      mail = ChatMessageMailer.new_message(message, [owner, other_staff])
      mail.deliver_now

      expect(mail.reply_to).to be_nil
      expect(mail.header["respond_to"].to_s).to eq(staff.email)
      expect(mail.to).to eq([owner.email, other_staff.email])
    end
  end

  describe "rendering" do
    it "renders an empty thread as an empty 200 body" do
      order = active_order!
      get chat_messages_path(job_order_id: order.id)
      expect(response).to have_http_status(:ok)
      expect(response.body.strip).to eq("")
    end

    it "still renders the thread of a soft-deleted order (plain JobOrder.find)" do
      order = active_order!
      ChatMessage.create!(job_order: order, sender: staff, message: "from the grave")
      order.update!(is_deleted: true)
      get chat_messages_path(job_order_id: order.id)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("from the grave")
    end

    # simple_format sanitizes (allow-list) rather than escapes: script tags are
    # stripped, harmless markup such as <b> passes through
    it "sanitizes HTML in a message in the thread (script stripped, <b> kept, & escaped)" do
      order = active_order!
      ChatMessage.create!(job_order: order, sender: owner, message: "<script>alert(1)</script> & <b>bold</b>")
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
