# frozen_string_literal: true

require "rails_helper"

# The quote mail lists every task of the order with its service, group, options and the price quoted for each option.
# What it reads per task and option must not cost queries that grow with the order.
RSpec.describe JobOrderMailer, type: :mailer do
  include JobOrderSpecHelpers

  let(:owner) { create(:user, :regular_user) }
  let(:order) { make_job_order!(owner: owner, status_key: :user_approval) }
  let(:job_type) { JobType.find_by!(name: "3D Print") }
  let(:group) { JobServiceGroup.create!(name: "Group #{SecureRandom.hex(3)}", job_type: job_type) }

  before do
    seed_job_statuses!
    seed_job_types!
    ActionMailer::Base.deliveries.clear
  end

  def add_task(title)
    service = JobService.create!(name: "Service #{title}", job_service_group: group, unit: "hour")
    order.job_tasks.create!(title: title, job_type: job_type, job_service: service).tap do |task|
      task.build_job_task_quote(price: 10, service_price: 2, service_quantity: 3).save!
      quoted = JobOption.create!(name: "Quoted #{title}", fee: 1)
      unquoted = JobOption.create!(name: "Unquoted #{title}", fee: 1)
      task.job_task_options.create!(job_option: quoted)
      task.job_task_options.create!(job_option: unquoted)
      task.job_task_quote.job_task_quote_options.create!(job_option: quoted, price: 4.5)
    end
  end

  def mail_text
    html = (ActionMailer::Base.deliveries.last.html_part || ActionMailer::Base.deliveries.last).body.decoded
    Nokogiri::HTML(html).text.gsub(/[[:space:]]+/, " ")
  end

  def deliver_queries
    count_queries { described_class.send_job_quote(order.id).deliver_now }
  end

  it "shows each task's service, group and the quoted price of each option, and 0 for an option with no quote" do
    add_task("Alpha")
    add_task("Beta")
    described_class.send_job_quote(order.id).deliver_now

    english = "Hello," + mail_text.split("Hello,").last
    expect(english).to include("- Alpha (Service Alpha - #{group.name} ) : CAD $16.00", "Grand Total: CAD $41.00")
    expect(english).to include("• Quoted Alpha : CAD $4.50", "• Unquoted Alpha : CAD $0.00")
    expect(english.index("- Alpha")).to be < english.index("- Beta")
    expect(english).to include("• Quoted Beta : CAD $4.50", "• Unquoted Beta : CAD $0.00")
  end

  it "runs the same number of queries for more tasks" do
    2.times { |i| add_task("Task #{i}") }
    deliver_queries # the first run also warms caches
    few = deliver_queries
    2.times { |i| add_task("More #{i}") }
    many = deliver_queries

    expect(many).to eq(few)
  end
end
