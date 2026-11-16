# frozen_string_literal: true

require "rails_helper"

# Wizard step 3 disables a job-wide option that another task of the order already selected, and explains why
# in the page language.
RSpec.describe "Job order wizard options step language", type: :request do
  let(:owner) { create(:user, :regular_user) }
  let(:order) { make_job_order!(owner: owner) }
  let(:job_type) { JobType.find_by!(name: "3D Print") }
  let(:task) { order.job_tasks.create!(title: "Task #1", job_type: job_type) }
  let(:other_task) { order.job_tasks.create!(title: "Task #2", job_type: job_type) }

  before do
    seed_job_statuses!
    seed_job_types!
    shared = create(:job_option, name: "Shared option", is_job_wide: true, need_files: false, is_deleted: false)
    job_type.job_options << shared
    other_task.job_task_options.create!(job_option: shared)
    task
    session_login!(owner)
  end

  def warning
    Nokogiri::HTML(response.body).at_css(".alert-warning").text.squish
  end

  it "explains in English why the option is disabled and links to the other task" do
    get edit_job_order_job_task_path(order, task, step: 3, locale: "en")

    expect(warning).to eq("This option is already selected on another task in this job order. Remove it from that task first")
  end

  it "explains in French why the option is disabled and links to the other task" do
    get edit_job_order_job_task_path(order, task, step: 3, locale: "fr")

    expect(warning).to eq("Cette option est déjà sélectionnée pour une autre tâche de cette commande. La retirer d'abord de cette tâche")
  end
end
