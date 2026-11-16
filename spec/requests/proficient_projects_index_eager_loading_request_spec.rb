# frozen_string_literal: true

require "rails_helper"

# The proficient projects page shows each project's own order items, photo, training and
# requirements; with Bullet raising under CI=1 a page of several projects that loads these one
# project at a time fails.
RSpec.describe "Proficient projects page", type: :request do
  include ContentSpecHelpers

  let(:user) { create(:user, :regular_user) }
  let(:skill) { create(:skill) }

  def add_training_with_projects(name, count)
    training = create(:training, skill: skill, name_en: name)
    Array.new(count) do |i|
      project = create(:proficient_project, training: training, title: "#{name} project #{i}", level: %w[Beginner Intermediate Advanced][i % 3])
      create(:photo, proficient_project: project)
      create(:training_requirement, proficient_project: project, training: create(:training, skill: skill), level: "Beginner")
      project
    end
  end

  it "renders several projects with their status buttons without a query per project" do
    first, second, = add_training_with_projects("Alpha", 4)
    add_training_with_projects("Beta", 2)
    order = create(:order, :completed, user: user)
    create(:order_item, proficient_project: first, order: order, status: "In progress")
    create(:order_item, proficient_project: second, order: order, status: "Awarded")
    content_login!(user)

    get proficient_projects_path

    expect(response).to have_http_status(:ok)
    expect(response.body.scan(/(?:Alpha|Beta) project \d/).uniq.size).to eq(6)
    expect(response.body.scan("pp-status-button").size).to eq(2)
  end

  it "lists a training's projects by level with the Advanced ones last" do
    add_training_with_projects("Gamma", 3)
    content_login!(user)

    get proficient_projects_path

    titles = response.body.scan(/Gamma project \d/).uniq
    expect(titles).to eq(["Gamma project 0", "Gamma project 1", "Gamma project 2"])
  end

  it "shows the blocked, added and add buttons by the user's requirements and cart" do
    project_met, project_unmet, project_in_cart = add_training_with_projects("Delta", 3)
    project_met.training_requirements.each do |requirement|
      create(:certification, user: user, training: requirement.training, level: "Beginner")
    end
    cart = create(:order, user: user)
    create(:order_item, proficient_project: project_in_cart, order: cart, status: "In progress")
    content_login!(user)

    get proficient_projects_path

    expect(project_unmet).to be_present
    expect(response.body.scan(CGI.escapeHTML(I18n.t("devprog.proficient_project.block"))).size).to eq(1)
    expect(response.body.scan(I18n.t("devprog.proficient_project.added")).size).to eq(1)
    expect(response.body.scan("cart-button").size).to eq(1)
  end

  it "renders when every visible project is already bought or in progress" do
    projects = add_training_with_projects("Epsilon", 2)
    order = create(:order, :completed, user: user)
    projects.each { |project| create(:order_item, proficient_project: project, order: order, status: "In progress") }
    content_login!(user)

    get proficient_projects_path

    expect(response).to have_http_status(:ok)
    expect(response.body.scan("pp-status-button").size).to eq(2)
  end
end
