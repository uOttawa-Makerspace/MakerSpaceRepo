# frozen_string_literal: true

require "rails_helper"

# JOB-01 (owner decision 2026-10-30): any change through the task wizard
# (JobTasksController create / update / destroy) to an order that has already
# been quoted sends the order back to staff for a new quote and voids the
# existing invoice. One domain operation, JobOrder#apply_owner_change!, holds
# the rule:
#   DRAFT, STAFF_APPROVAL        applied, status unchanged
#   USER_APPROVAL .. COMPLETED   applied + a STAFF_APPROVAL row (who + why), the
#                                old approve link dies, the Shopify draft is
#                                deleted (fail closed), staff are mailed after
#                                the commit
#   PAID, PICKED_UP              refused, nothing changes
#   DECLINED                     applied, status unchanged (as before)
RSpec.describe "Owner changes after the quote (JOB-01)", type: :request do
  let(:owner) { create(:user, :regular_user) }
  let(:staff) { create(:user, :staff) }
  let(:admin) { create(:user, :admin) }
  let(:print_type) { JobType.find_by!(name: "3D Print") }
  let(:laser_type) { JobType.find_by!(name: "Laser Cut") }
  let!(:shopify) { stub_shopify_admin!.tap { |fake| fake.invoice_url = "https://pay.example/old-invoice" } }

  quoted = %i[user_approval sent_reminder waiting_processed being_processed completed]
  not_quoted = %i[draft staff_approval]
  money_taken = %i[paid picked_up]

  before do
    seed_job_statuses!
    seed_job_order_message!
    seed_job_types!
    ActionMailer::Base.deliveries.clear
  end

  def status_rows(order)
    order.reload.job_order_statuses.order(:id).to_a
  end

  def status_names(order)
    status_rows(order).map { |s| s.job_status.name }
  end

  def shopify_ops
    shopify.calls.map { |c| c[:query][/\b(draftOrder\w+|getDraftOrder)\b/] }
  end

  def status_row(key)
    JobStatus.find_by!(name: JobOrderSpecHelpers::JOB_STATUS_NAMES.fetch(key))
  end

  # A realistic history for `status_key`: submitted (STAFF_APPROVAL), quoted
  # (USER_APPROVAL), then the target state. Two typed tasks:
  #   Task #1: 40 base + Polish option quoted at 4   Task #2: 10 base   => 54
  def order_in!(status_key, draft: false)
    order = create(:job_order, user: owner)
    history = case status_key
              when :draft then [:draft]
              when :staff_approval then %i[draft staff_approval]
              when :user_approval then %i[draft staff_approval user_approval]
              else %i[draft staff_approval user_approval] + [status_key]
              end
    history.each do |key|
      order.job_order_statuses.create!(job_status: status_row(key), user: key == :draft ? owner : staff)
    end

    polish = JobOption.find_by(name: "Polish") ||
             JobOption.create!(name: "Polish", fee: 1).tap { |o| o.job_types << print_type }
    task1 = order.job_tasks.create!(title: "Task #1", job_type: print_type)
    task1.job_task_options.create!(job_option: polish)
    task1.build_job_task_quote(price: 40, service_price: 0, service_quantity: 0).save!
    task1.job_task_quote.job_task_quote_options.create!(job_option: polish, price: 4)
    task2 = order.job_tasks.create!(title: "Task #2", job_type: print_type)
    task2.build_job_task_quote(price: 10, service_price: 0, service_quantity: 0).save!
    order.update_column(:shopify_draft_order_id, "gid://shopify/DraftOrder/9001") if draft
    order.reload
  end

  def task1(order) = order.job_tasks.find_by!(title: "Task #1")
  def task2(order) = order.job_tasks.find_by!(title: "Task #2")

  # Every write the wizard can make. `act` sends the request; `applied?` says
  # whether the change landed.
  def self.wizard_paths = {
    "create a task" => {
      act: ->(o) { post job_order_job_tasks_path(o) },
      applied?: ->(o) { o.job_tasks.count == 3 }
    },
    "change a task's job type (step 1)" => {
      act: lambda do |o|
        patch job_order_job_task_path(o, task1(o)), params: { step: "1", job_task: { job_type_id: laser_type.id } }
      end,
      applied?: ->(o) { task1(o).job_type == laser_type }
    },
    "deselect a quoted option (step 3)" => {
      act: ->(o) { patch job_order_job_task_path(o, task1(o)), params: { step: "3" } },
      applied?: ->(o) { task1(o).job_task_options.none? && task1(o).job_task_quote.job_task_quote_options.none? }
    },
    "upload a file (step 2)" => {
      act: lambda do |o|
        patch job_order_job_task_path(o, task1(o)), params: { step: "2", job_task: { user_files: [FilesTestHelper.stl] } }
      end,
      applied?: ->(o) { task1(o).user_files.attached? }
    },
    "enter a custom service (step 2)" => {
      act: lambda do |o|
        group = JobServiceGroup.create!(name: "Material", job_type: print_type)
        patch job_order_job_task_path(o, task1(o)),
              params: { step: "2", "job_service_name_#{group.id}" => "Glow PLA",
                        job_task: { job_service_id: "custom" } }
      end,
      applied?: ->(o) { task1(o).job_service&.name == "Glow PLA" }
    },
    "post wizard comments (step 4)" => {
      act: lambda do |o|
        patch job_order_job_task_path(o, task1(o)), params: { step: "4", comments: "make it blue", save_draft: "true" }
      end,
      applied?: ->(o) { o.chat_messages.exists?(message: "make it blue") }
    },
    "add another task (step 4)" => {
      act: ->(o) { patch job_order_job_task_path(o, task1(o)), params: { step: "4", add_another: "true" } },
      applied?: ->(o) { o.job_tasks.count == 3 }
    },
    "delete a task" => {
      act: ->(o) { delete job_order_job_task_path(o, task2(o)) },
      applied?: ->(o) { !o.job_tasks.exists?(title: "Task #2") }
    }
  }

  def run_path(name, order)
    instance_exec(order, &self.class.wizard_paths.fetch(name)[:act])
  end

  def applied?(name, order)
    instance_exec(order.reload, &self.class.wizard_paths.fetch(name)[:applied?])
  end

  def snapshot(order)
    order.reload
    {
      statuses: order.job_order_statuses.order(:id).pluck(:id),
      tasks: order.job_tasks.order(:id).map { |t| [t.id, t.job_type_id, t.job_service_id, t.user_files.count] },
      options: JobTaskOption.where(job_task: order.job_tasks).order(:id).pluck(:id),
      quote_options: JobTaskQuoteOption.joins(:job_task_quote)
                                       .where(job_task_quotes: { job_task_id: order.job_tasks.select(:id) }).pluck(:id),
      total: order.total_price,
      draft: order.shopify_draft_order_id,
      chat: order.chat_messages.count
    }
  end

  # [order id, ...] of every enqueued "needs a new quote" staff mail
  def requote_mails
    ActiveJob::Base.queue_adapter.enqueued_jobs
                   .select { |j| j[:job] == ActionMailer::MailDeliveryJob && j[:args].first(2) == %w[JobOrderMailer send_job_requote_needed] }
                   .map { |j| j[:args].last["args"].first }
  end

  def expect_requote_mail(order)
    expect(requote_mails).to eq([order.id])
  end

  def expect_no_requote_mail
    expect(requote_mails).to be_empty
  end

  # ------------------------------------------------------------ status buckets

  describe "by status" do
    not_quoted.each do |key|
      it "applies the change and keeps the status in #{key} (not yet quoted)" do
        order = order_in!(key)
        before = status_names(order)
        session_login!(owner)
        run_path("change a task's job type (step 1)", order)

        expect(applied?("change a task's job type (step 1)", order)).to be(true)
        expect(status_names(order)).to eq(before)
        expect(shopify.calls).to be_empty
        expect_no_requote_mail
      end
    end

    quoted.each do |key|
      it "applies the change and sends the order back to staff from #{key}" do
        order = order_in!(key, draft: key == :completed)
        session_login!(owner)
        run_path("change a task's job type (step 1)", order)

        expect(applied?("change a task's job type (step 1)", order)).to be(true)
        back = status_rows(order).last
        expect(back.job_status.name).to eq("Waiting for Staff Approval")
        expect(back.user).to eq(owner)
        expect(back.reason).to eq("owner_change")
        expect(flash[:notice]).to eq(I18n.t("job_orders.alerts.order_sent_back_for_requote"))
        expect_requote_mail(order)
        if key == :completed
          expect(shopify_ops).to eq(["draftOrderDelete"])
          expect(order.reload.shopify_draft_order_id).to be_nil
        end
      end
    end

    money_taken.each do |key|
      %w[en fr].each do |locale|
        it "refuses the change on a #{key} order and says why (#{locale})" do
          order = order_in!(key, draft: true)
          before = snapshot(order)
          session_login!(owner)
          patch job_order_job_task_path(order, task1(order)),
                params: { locale: locale, step: "1", job_task: { job_type_id: laser_type.id } }

          expect(response).to redirect_to(job_order_path(order))
          expect(flash[:alert]).to eq(I18n.t("job_orders.alerts.paid_order_cannot_change", locale: locale))
          expect(snapshot(order)).to eq(before)
          expect(shopify.calls).to be_empty
          expect_no_requote_mail
        end
      end
    end

    it "keeps today's behaviour on a DECLINED order: applied, still Declined, nobody told" do
      order = order_in!(:declined)
      before = status_names(order)
      session_login!(owner)
      run_path("delete a task", order)

      expect(applied?("delete a task", order)).to be(true)
      expect(status_names(order)).to eq(before)
      expect(shopify.calls).to be_empty
      expect_no_requote_mail
    end
  end

  # ------------------------------------------------------------ every path

  describe "every wizard write on a quoted order with a live invoice" do
    wizard_paths.each_key do |name|
      it "#{name}: applied, back to staff, invoice voided, staff mailed" do
        order = order_in!(:completed, draft: true)
        session_login!(owner)
        run_path(name, order)

        expect(applied?(name, order)).to be(true)
        expect(status_rows(order).last)
          .to have_attributes(job_status: JobStatus::STAFF_APPROVAL, user: owner, reason: "owner_change")
        expect(shopify_ops).to eq(["draftOrderDelete"])
        expect(order.reload.shopify_draft_order_id).to be_nil
        expect_requote_mail(order)
      end
    end

    wizard_paths.each_key do |name|
      it "#{name}: refused on a PAID order, nothing changes" do
        order = order_in!(:paid, draft: true)
        before = snapshot(order)
        session_login!(owner)
        run_path(name, order)

        expect(flash[:alert]).to eq(I18n.t("job_orders.alerts.paid_order_cannot_change"))
        expect(snapshot(order)).to eq(before)
        expect(shopify.calls).to be_empty
      end
    end

    it "applies the same rule to an admin editing through the wizard (the admin is recorded)" do
      order = order_in!(:user_approval)
      session_login!(admin)
      run_path("delete a task", order)

      expect(applied?("delete a task", order)).to be(true)
      expect(status_rows(order).last)
        .to have_attributes(job_status: JobStatus::STAFF_APPROVAL, user: admin, reason: "owner_change")
    end
  end

  # ------------------------------------------------------------ old quote retired

  describe "the old quote can no longer be approved" do
    it "kills the emailed approve link, also after a staff reminder and a re-quote" do
      order = order_in!(:user_approval)
      old_token = order.approval_token
      session_login!(owner)
      run_path("delete a task", order)

      get user_magic_approval_job_orders_path, params: { token: old_token }
      expect(flash[:alert]).to eq(I18n.t("job_orders.alerts.approval_magic_link_expired"))

      patch user_magic_approval_confirmation_job_orders_path, params: { token: old_token, approved: "true" }
      expect(status_names(order).last).to eq("Waiting for Staff Approval")

      # staff cannot resurrect it with a reminder: there is no live quote to remind about
      session_login!(staff)
      patch job_order_resend_quote_email_path(order)
      expect(status_names(order).last).to eq("Waiting for Staff Approval")
      expect(JobOrder.from_approval_token(old_token)).to be_nil

      # a new quote issues a new link; the old one stays dead
      patch job_order_quote_path(order), params: { approved: "true", "job_task_quote_price_#{task1(order).id}" => "60",
                                                   job_order: { staff_comments: "" } }
      expect(status_names(order).last).to eq("Waiting for User Approval")
      expect(JobOrder.from_approval_token(old_token)).to be_nil
      expect(JobOrder.from_approval_token(order.reload.approval_token)).to eq(order)
    end
  end

  # ------------------------------------------------------------ fail closed

  describe "when Shopify cannot delete the invoice" do
    {
      "Shopify answers 502" => ->(fake) { fake.status = 502 },
      "the draft is already completed (userErrors, still found)" =>
        ->(fake) { fake.delete_user_errors = [{ "field" => "id", "message" => "cannot delete a completed draft order" }] }
    }.each do |label, break_shopify|
      it "refuses the owner's change and changes nothing (#{label})" do
        order = order_in!(:completed, draft: true)
        before = snapshot(order)
        break_shopify.call(shopify)
        session_login!(owner)
        run_path("delete a task", order)

        expect(response).to redirect_to(job_order_path(order))
        expect(flash[:alert]).to eq(I18n.t("job_orders.alerts.owner_change_draft_order_failed"))
        expect(snapshot(order)).to eq(before)
        expect_no_requote_mail
      end
    end
  end

  # ------------------------------------------------------------ what staff see

  describe "pages", skip_bullet: true do
    it "shows staff in the timeline who sent the order back and why" do
      order = order_in!(:completed)
      session_login!(owner)
      run_path("delete a task", order)

      session_login!(staff)
      get job_order_timeline_modal_path(order)
      text = Nokogiri::HTML(response.body).text.squish
      expect(text).to include("#{I18n.t('job_orders.status_reasons.owner_change')} (By: #{owner.name})")
    end

    it "offers an admin the task Edit / Add buttons until the order is paid" do
      session_login!(admin)
      quoted = order_in!(:completed)
      get job_order_path(quoted)
      expect(response.body).to include(edit_job_order_job_task_path(quoted, task1(quoted), step: 1))

      paid = order_in!(:paid)
      get job_order_path(paid)
      expect(response.body).not_to include(edit_job_order_job_task_path(paid, task1(paid), step: 1))
      expect(response.body).not_to include(job_order_job_tasks_path(paid))
    end
  end

  # ------------------------------------------------------------ lock + commit

  describe "lock and transaction boundaries" do
    it "reads the status under the row lock (a payment that commits first wins)" do
      order = order_in!(:completed)
      before_tasks = order.job_tasks.count
      allow_any_instance_of(JobOrder).to receive(:lock!).and_wrap_original do |m, *args|
        # staff mark the order paid just before this request gets the lock
        unless JobOrderStatus.exists?(job_order_id: order.id, job_status: JobStatus::PAID)
          JobOrderStatus.create!(job_order_id: order.id, job_status: JobStatus::PAID, user: staff)
        end
        m.call(*args)
      end
      session_login!(owner)
      run_path("delete a task", order)

      expect(flash[:alert]).to eq(I18n.t("job_orders.alerts.paid_order_cannot_change"))
      # (the stand-in PAID row was written inside the refused transaction, so it rolls back with it)
      expect(order.reload.job_tasks.count).to eq(before_tasks)
      expect(status_names(order).count("Waiting for Staff Approval")).to eq(1)
    end

    it "mails staff only after the change has committed" do
      order = order_in!(:completed, draft: true)
      baseline = JobOrder.connection.open_transactions
      open_at_mail = nil
      allow(JobOrderMailer).to receive(:send_job_requote_needed).and_wrap_original do |m, *args|
        open_at_mail = JobOrder.connection.open_transactions
        m.call(*args)
      end
      session_login!(owner)
      run_path("delete a task", order)

      expect(open_at_mail).to eq(baseline)
    end
  end
end
