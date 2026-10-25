# frozen_string_literal: true

require "rails_helper"

# End-to-end job order journey through the real UI: the user walks the wizard
# (file upload + option), staff quote it, the user approves from the magic link
# in the delivered mail, staff process / mark paid / mark picked up, and both
# sides chat. Pins current behavior (D-J19: the landing page's "Start
# Production" button creates a typeless task, so the wizard's step 1 asks for
# the job type).
RSpec.describe "Journey: job order", type: :system do
  let!(:user) { create(:user, :regular_user) }
  let!(:staff) { create(:user, :admin) }
  let(:fixture) { Rails.root.join("spec/support/assets/test.stl") }

  before do
    seed_job_statuses!
    seed_job_order_message!
    seed_job_types!
    JobType.find_by!(name: "3D Print").update!(service_fee: 5, file_description: "Upload your STL", multiple_files: false)
    @option = create(:job_option, name: "Support removal", fee: 2.5, need_files: false, description: "We remove supports")
    @option.job_types << JobType.find_by!(name: "3D Print")
    ActionMailer::Base.deliveries.clear
  end

  def walk_wizard_as_user
    log_in_as(user)
    visit landing_job_orders_path
    click_link "Start a Job Order"
    click_button "Start Production"
    expect(page).to have_current_path(%r{\A/job_orders/\d+/task/\d+/edit\z}, ignore_query: true)

    # step 1: job type (the landing button's JS is broken, D-J19/D-JS01)
    expect(page).to have_content("Job Type (required)*")
    select "3D Print", from: "job_type_select"
    expect(page).to have_css("#job_type_#{JobType.find_by!(name: '3D Print').id}_description", text: /3D Printed/i)
    click_button "Next Step"

    # step 2: file upload
    expect(page).to have_content("Upload your STL")
    attach_file "job_task[user_files][]", fixture
    click_button "Next Step"

    # step 3: options
    expect(page).to have_content("Support removal")
    check "job_task_option_#{@option.id}"
    click_button "Next Step"

    # step 4: comment + submit
    expect(page).to have_content("Step 4/4").or have_css("textarea#comments")
    fill_in "comments", with: "Please print in grey"
    click_button "Submit"
  end

  it "wizard -> staff quote -> magic-link approval -> processed -> paid -> picked up, with chat" do
    as_actor(:user) do
      walk_wizard_as_user
      expect(page).to have_current_path(%r{\A/job_orders/\d+\z})
      expect(page).to have_content("Waiting for Staff Approval")
      expect(page).to have_content("Client Files")
      expect(page).to have_content("Please print in grey") # wizard comment lands in the chat
      expect(page).to have_content("Support removal")
    end

    order = JobOrder.order(:id).last
    task = order.job_tasks.first
    expect(order.user).to eq(user)
    expect(order.job_order_statuses.last.job_status.name).to eq("Waiting for Staff Approval")
    expect(task.job_type.name).to eq("3D Print")
    # JobTask#set_filename renames the blob to "<task id>_<original name>"
    expect(task.user_files.map { |f| f.filename.to_s }).to eq(["#{task.id}_test.stl"])
    expect(task.job_options).to eq([@option])
    expect(deliver_mail.map(&:subject)).to include("A new Job Order has been submitted")
    expect(ActionMailer::Base.deliveries.find { |m| m.subject == "A new Job Order has been submitted" }.to).to eq(["makerspace@uottawa.ca"])

    # staff approve with a quote
    as_actor(:staff) do
      log_in_as(staff)
      visit admin_job_orders_path
      expect(page).to have_css("table", text: user.name)
      visit job_order_path(order)
      expect(page).to have_content("Waiting for Staff Approval")
      click_button "Approve", match: :first
      within("#quote-modal") do
        expect(page).to have_field("job_task_quote_price_#{task.id}", visible: true)
        fill_in "job_task_quote_price_#{task.id}", with: "12.50"
        fill_in "user_comments", with: "Quote is ready"
        click_button "Approve"
      end
      expect(page).to have_content("Waiting for User Approval")
    end
    expect(order.reload.job_order_statuses.last.job_status.name).to eq("Waiting for User Approval")
    expect(order.job_tasks.first.job_task_quote.price).to eq(12.5)
    quote_mail = deliver_mail.find { |m| m.subject.include?("Your job order ##{order.id} has been approved") }
    expect(quote_mail.to).to eq([user.email])
    magic_path = link_path_in_mail(quote_mail, %r{/job_orders/user_magic_approval})

    # the user follows the link from the mail in their signed-in browser (a
    # signed-out browser cannot approve, see the D-J09 example below)
    as_actor(:user) do
      visit magic_path
      expect(page).to have_content("Thank You for ordering a Job Order!")
      expect(page).to have_content("Total Quote")
      click_button "Approve the Quote"
      expect(page).to have_content("Thank You for Approving/Denying the Job Order!")
    end
    expect(order.reload.job_order_statuses.last.job_status.name).to eq("Waiting to be Processed")

    as_actor(:staff) do
      visit job_order_path(order)
      click_button "Start Processing"
      expect(page).to have_content("Currently being Processed")
      click_button "Completed"
      within("#completed-email-modal") do
        click_button "Do not send email and mark completed"
      end
      expect(page).to have_content("Completed (Waiting for Payment)")
      expect(page).to have_content("Price: $15.00") # 12.50 base fee + 2.50 option
      # WART(D-E2E05): the Invoice button label shows its icon markup as text
      expect(page).to have_link("<i class='fa fa-download'></i> Invoice")
      click_button "Mark as Paid"
      expect(page).to have_content("Paid (Waiting for Pick-Up)")
      click_button "Mark as Picked Up"
      expect(page).to have_content("Picked-Up")
    end
    expect(order.reload.job_order_statuses.map { |s| s.job_status.name }).to eq(
      ["Draft", "Waiting for Staff Approval", "Waiting for User Approval", "Waiting to be Processed",
       "Currently being Processed", "Completed (Waiting for Payment)", "Paid (Waiting for Pick-Up)", "Picked-Up"]
    )

    # chat, both directions (signed-in users only: a guest POST poisons the page, D-J25)
    as_actor(:user) do
      visit job_order_path(order)
      expect(page).to have_content("Quote is ready")
      fill_in "chat_message[message]", with: "Thanks, when can I collect?"
      click_button "Send"
      expect(page).to have_field("chat_message[message]", with: "")
    end
    expect(ChatMessage.where(job_order: order, sender: user).order(:id).pluck(:message).last).to eq("Thanks, when can I collect?")
    as_actor(:staff) do
      visit job_order_path(order)
      within("#chat-messages") { expect(page).to have_content("Thanks, when can I collect?") }
      fill_in "chat_message[message]", with: "Tomorrow after 10"
      click_button "Send"
      expect(page).to have_field("chat_message[message]", with: "")
    end
    as_actor(:user) do
      visit job_order_path(order)
      within("#chat-messages") do
        expect(page).to have_content("Tomorrow after 10")
        expect(page).to have_content("(staff)")
      end
    end
    expect(ChatMessage.where(job_order: order).order(:id).pluck(:message)).to eq(
      ["Please print in grey", "Quote is ready", "Thanks, when can I collect?", "Tomorrow after 10"]
    )
  end

  it "pinned: following the quote magic link while signed out cannot approve (D-J09)" do
    order = make_job_order!(owner: user, status_key: :user_approval, staff: staff)
    task = order.job_tasks.create!(title: "Task #1", job_type: JobType.find_by!(name: "3D Print"))
    ActionMailer::Base.deliveries.clear
    path = "/job_orders/user_magic_approval?token=#{CGI.escape(magic_link_token_for(order))}"

    as_actor(:phone) do
      visit path
      expect(page).to have_content("Thank You for ordering a Job Order!")
      click_button "Approve the Quote"
      # WART(D-J09): @user is the blank guest User.new, so the status row is invalid
      expect(page).to have_content("An error occured while trying to Approve/Deny the Job Order...")
      expect(page).to have_content("An error occurred while updating the Job Order Status")
    end
    expect(order.reload.job_order_statuses.last.job_status.name).to eq("Waiting for User Approval")
    expect(task.reload).to be_persisted
    expect(deliver_mail).to be_empty
  end
end
