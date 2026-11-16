# frozen_string_literal: true

require "rails_helper"

# The order page for each viewer and status: who is let in, which notices it shows, which chat messages it marks
# read, and what the staff section reads (the staff list and the processed mail text).
RSpec.describe "Job order show page", type: :request do
  let(:owner) { create(:user, :regular_user) }
  let(:staff) { create(:user, :staff) }
  let(:admin) { create(:user, :admin) }
  let(:stranger) { create(:user, :regular_user) }
  let(:action_required) { I18n.t("job_orders.alerts.action_required_scroll_to_timeline") }

  before do
    seed_job_statuses!
    seed_job_order_message!
    seed_job_types!
  end

  def typed_task!(order, title)
    order.job_tasks.create!(title: title, job_type: JobType.find_by!(name: "3D Print"))
  end

  def order_in(status_key)
    make_job_order!(owner: owner, status_key: status_key).tap { |o| typed_task!(o, "Task #1") }
  end

  describe "who may open it" do
    it "sends everyone to the order list with a message when the order does not exist" do
      session_login!(staff)
      get job_order_path(0)
      expect(response).to redirect_to(job_orders_path)
      expect(flash[:alert]).to eq(I18n.t("job_orders.alerts.job_order_not_found"))
    end

    it "treats a deleted order as missing, even for its owner" do
      order = order_in(:draft)
      order.update_column(:is_deleted, true) # rubocop:disable Rails/SkipsModelValidations
      session_login!(owner)
      get job_order_path(order)
      expect(response).to redirect_to(job_orders_path)
      expect(flash[:alert]).to eq(I18n.t("job_orders.alerts.job_order_not_found"))
    end

    it "sends another regular user to the new order page with a message" do
      order = order_in(:draft)
      session_login!(stranger)
      get job_order_path(order)
      expect(response).to redirect_to(new_job_orders_path)
      expect(flash[:alert]).to eq(I18n.t("job_orders.alerts.no_permission"))
    end

    { owner: [false, false], staff: [true, false], admin: [true, true] }.each do |role, (staff_section, staff_select)|
      it "renders for the #{role} (staff section: #{staff_section}, staff list: #{staff_select})" do
        order = order_in(:waiting_processed)
        other_staff = create(:user, :staff, name: "Other Staffer")
        session_login!(public_send(role))
        get job_order_path(order)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Job Order ##{order.id}")
        processed = CGI.escapeHTML(JobOrderMessage.find_by!(name: "processed").retrieve_message(order.id))
        expect(response.body.include?(%(id="job-order-message" value="#{processed}"))).to be(staff_section)
        expect(response.body.include?(%(id="jo-staff-select-#{order.id}"))).to be(staff_select)
        expect(response.body.include?(%(<option value="#{other_staff.id}">Other Staffer</option>))).to be(staff_select)
        expect(flash[:alert]).to be_nil
        expect(flash[:notice]).to be_nil
      end
    end
  end

  describe "the action required notice" do
    JobStatus::STATUS_NAMES.each_key do |status_key|
      shown = %i[user_approval sent_reminder completed].include?(status_key)

      it "is #{shown ? '' : 'not '}shown to the owner in #{status_key}" do
        order = order_in(status_key)
        session_login!(owner)
        get job_order_path(order)
        expect(response).to have_http_status(:ok)
        expect(flash[:notice]).to eq(shown ? action_required : nil)
      end
    end

    %i[staff admin].each do |role|
      it "is not shown to #{role} viewing an order waiting for the user" do
        order = order_in(:user_approval)
        session_login!(public_send(role))
        get job_order_path(order)
        expect(response).to have_http_status(:ok)
        expect(flash[:notice]).to be_nil
      end
    end

    # An order without any status row has no current step: its timeline shows the eight usual steps, all still to
    # come, with none marked done or current.
    %i[owner staff].each do |role|
      it "is not set for an order without any status row, whose page #{role} can still open" do
        order = create(:job_order, user: owner)
        typed_task!(order, "Task #1")
        session_login!(public_send(role))
        get job_order_path(order)
        expect(response).to have_http_status(:ok)
        expect(flash[:notice]).to be_nil
        expect(response.body.scan("fa-solid fa-circle me-2 text-muted").size).to eq(8)
        expect(response.body).not_to include("fa-solid fa-check me-2 text-success", "fa-solid fa-dot_circle me-2")
      end
    end
  end

  describe "the missing information alert" do
    it "names every task without a job type, in creation order" do
      order = make_job_order!(owner: owner, status_key: :draft)
      order.job_tasks.create!(title: "Untyped A")
      typed_task!(order, "Typed")
      order.job_tasks.create!(title: "Untyped B")
      session_login!(owner)
      get job_order_path(order)
      expect(flash[:alert]).to eq("#{I18n.t('job_orders.alerts.missing_info')} Untyped A, Untyped B")
    end

    it "names a task whose job type has service groups but no chosen service" do
      order = make_job_order!(owner: owner, status_key: :draft)
      job_type = JobType.find_by!(name: "Laser Cut")
      create(:job_service_group, job_type: job_type)
      order.job_tasks.create!(title: "Needs service", job_type: job_type)
      session_login!(staff)
      get job_order_path(order)
      expect(flash[:alert]).to eq("#{I18n.t('job_orders.alerts.missing_info')} Needs service")
    end

    it "is shown together with the action required notice" do
      order = make_job_order!(owner: owner, status_key: :user_approval)
      order.job_tasks.create!(title: "Untyped")
      session_login!(owner)
      get job_order_path(order)
      expect(flash[:notice]).to eq(action_required)
      expect(flash[:alert]).to eq("#{I18n.t('job_orders.alerts.missing_info')} Untyped")
    end

    it "is not shown for an order without tasks" do
      order = make_job_order!(owner: owner, status_key: :draft)
      session_login!(owner)
      get job_order_path(order)
      expect(response).to have_http_status(:ok)
      expect(flash[:alert]).to be_nil
    end
  end

  describe "unread chat messages" do
    it "marks only the messages others sent as read when the owner opens it" do
      order = order_in(:user_approval)
      from_staff = ChatMessage.create!(job_order: order, sender: staff, message: "From staff")
      from_owner = ChatMessage.create!(job_order: order, sender: owner, message: "From owner")
      elsewhere = ChatMessage.create!(job_order: order_in(:draft), sender: staff, message: "Other order")
      session_login!(owner)
      get job_order_path(order)
      expect([from_staff, from_owner, elsewhere].map { |m| m.reload.is_read }).to eq([true, false, false])
    end

    %i[staff admin].each do |role|
      it "marks nothing read when #{role} opens it" do
        order = order_in(:user_approval)
        message = ChatMessage.create!(job_order: order, sender: owner, message: "From owner")
        session_login!(public_send(role))
        get job_order_path(order)
        expect(message.reload.is_read).to be(false)
      end
    end
  end
end
