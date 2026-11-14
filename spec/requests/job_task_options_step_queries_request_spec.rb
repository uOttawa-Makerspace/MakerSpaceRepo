# frozen_string_literal: true

require "rails_helper"

# Wizard step 3 lists the options of the task's job type. What it looks up for each option (the other task that
# already selected a job-wide option, the file already uploaded for the task) must not cost a query per option.
RSpec.describe "Job order wizard options step", type: :request do
  let(:owner) { create(:user, :regular_user) }
  let(:order) { make_job_order!(owner: owner) }
  let(:job_type) { JobType.find_by!(name: "3D Print") }
  let(:task) { order.job_tasks.create!(title: "Task #1", job_type: job_type) }
  let(:other_task) { order.job_tasks.create!(title: "Task #2", job_type: job_type) }

  before do
    seed_job_statuses!
    seed_job_types!
    task
    other_task
    # The warning copy for a job-wide option already used by another task has no locale entry yet; the test
    # environment raises on missing translations, so give it stand-in text for the rows that render it.
    I18n.backend.store_translations(
      :en,
      job_orders: { wizard: { step_3: { option_already_selected: "Already selected", remove_from_other_task: "Remove it" } } }
    )
    session_login!(owner)
  end

  after { I18n.backend.reload! }

  def add_option(name:, job_wide: false, need_files: false)
    create(:job_option, name: name, is_job_wide: job_wide, need_files: need_files, is_deleted: false).tap do |option|
      job_type.job_options << option
    end
  end

  def add_option_rows(count)
    count.times do |i|
      shared = add_option(name: "Shared #{SecureRandom.hex(2)} #{i}", job_wide: true)
      other_task.job_task_options.create!(job_option: shared)
      with_file = add_option(name: "Filed #{SecureRandom.hex(2)} #{i}", need_files: true)
      row = task.job_task_options.create!(job_option: with_file)
      row.option_file.attach(io: StringIO.new("data"), filename: "part#{i}.stl", content_type: "model/stl")
    end
  end

  def step_three_queries
    count_queries { get edit_job_order_job_task_path(order, task, step: 3) }
  end

  it "disables a job-wide option another task selected and links to that task" do
    shared = add_option(name: "Shared option", job_wide: true)
    free = add_option(name: "Free option", job_wide: true)
    other_task.job_task_options.create!(job_option: shared)

    get edit_job_order_job_task_path(order, task, step: 3)

    doc = Nokogiri::HTML(response.body)
    expect(doc.at_css("#job_task_option_#{shared.id}")["disabled"]).to be_present
    expect(doc.at_css("#job_task_option_#{free.id}")["disabled"]).to be_nil
    expect(doc.css("a").map { |a| a["href"] }).to include(edit_job_order_job_task_path(order, other_task, step: 3))
  end

  it "shows the file already uploaded for an option that needs one" do
    filed = add_option(name: "Needs file", need_files: true)
    row = task.job_task_options.create!(job_option: filed)
    row.option_file.attach(io: StringIO.new("data"), filename: "part.stl", content_type: "model/stl")

    get edit_job_order_job_task_path(order, task, step: 3)

    expect(response.body).to include("part.stl")
    expect(Nokogiri::HTML(response.body).at_css("#job_task_option_#{filed.id}")["checked"]).to be_present
    expect(Nokogiri::HTML(response.body).at_css("#job_task_option_file_#{filed.id}")).to be_present
  end

  it "runs the same number of queries for more options" do
    add_option_rows(1)
    step_three_queries
    add_option_rows(1)
    few = step_three_queries
    add_option_rows(2)
    many = step_three_queries

    expect(many).to eq(few)
  end
end
