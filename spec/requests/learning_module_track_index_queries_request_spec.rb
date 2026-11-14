# frozen_string_literal: true

require "rails_helper"

# The skills overview shows, for every training, the lowest level the signed-in user still has modules to do, how many
# of its modules they finished and which modules are next. Those are worked out from one load of the trainings'
# modules and of the user's completed modules, so the number of queries does not grow with the number of trainings.
RSpec.describe "Learning module track index queries", type: :request do
  let!(:user) { sign_in_as(:regular) }
  let(:skill) { create(:skill, name: "Fabrication") }

  def add_training(name, levels)
    create(:training, skill: skill, name_en: name, name_fr: "#{name} fr").tap do |training|
      levels.each_with_index { |level, i| create(:learning_module, training: training, level: level, title: "#{name} m#{i}") }
    end
  end

  def complete(*titles)
    titles.each { |title| create(:learning_module_track, :completed, user: user, learning_module: LearningModule.find_by!(title: title)) }
  end

  def accordion(training)
    Nokogiri::HTML(response.body).at_css("#accordion-#{training.id}")
  end

  def summary(training)
    node = accordion(training)
    {
      level: node.at_css(".accordion-header p span").text,
      finished: node.at_css(".accordion-body p:nth-of-type(2)").text.squish,
      next: node.css(".accordion-body li a").map(&:text)
    }
  end

  it "shows each training's lowest open level, finished count and next modules for the signed-in user" do
    beginner = add_training("Laser", %w[Beginner Intermediate Advanced])
    intermediate = add_training("Print", %w[Beginner Intermediate General])
    advanced = add_training("Weld", %w[Advanced General])
    master = add_training("Mill", %w[Beginner General])
    empty = add_training("Saw", [])
    complete("Print m0", "Mill m0", "Mill m1")
    create(:learning_module_track, user: user, learning_module: LearningModule.find_by!(title: "Laser m0"))
    create(:learning_module_track, :completed, user: create(:user, :regular_user), learning_module: LearningModule.find_by!(title: "Weld m0"))

    get learning_module_track_index_path

    expect(response).to have_http_status(:ok)
    expect(summary(beginner)).to eq(level: "Beg", finished: "Modules finished : 0 / 3", next: ["Laser m0", "Laser m1", "Laser m2"])
    expect(summary(intermediate)).to eq(level: "Int", finished: "Modules finished : 1 / 3", next: ["Print m1", "Print m2"])
    expect(summary(advanced)).to eq(level: "Adv", finished: "Modules finished : 0 / 2", next: ["Weld m0", "Weld m1"])
    expect(summary(master)).to eq(level: "Master", finished: "Modules finished : 2 / 2", next: [])
    expect(summary(empty)).to eq(level: "Master", finished: "Modules finished : 0 / 0", next: [])
  end

  it "lists the next modules in their set order" do
    training = add_training("Laser", %w[Beginner Beginner Beginner])
    LearningModule.find_by!(title: "Laser m0").update_columns(order: 3)
    LearningModule.find_by!(title: "Laser m1").update_columns(order: 2)
    LearningModule.find_by!(title: "Laser m2").update_columns(order: 1)

    get learning_module_track_index_path

    expect(summary(training)[:next]).to eq(["Laser m2", "Laser m1", "Laser m0"])
  end

  it "runs the same number of queries for one training as for four" do
    add_training("Laser", %w[Beginner Advanced])
    complete("Laser m0")
    get learning_module_track_index_path
    one = count_queries { get learning_module_track_index_path }

    add_training("Print", %w[Beginner Intermediate])
    add_training("Weld", %w[Advanced])
    add_training("Mill", %w[General Beginner])
    complete("Print m0", "Weld m0")
    four = count_queries { get learning_module_track_index_path }

    expect(response).to have_http_status(:ok)
    expect(four).to eq(one)
  end
end
