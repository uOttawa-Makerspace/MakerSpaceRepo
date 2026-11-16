# frozen_string_literal: true

require "rails_helper"

# The learning area index shows, for every training and level, how many modules the signed-in user completed. Those
# counts are worked out from one load of the user's completed modules, not by a query per training and level.
RSpec.describe "Learning area index progress counts", type: :request do
  let!(:user) { sign_in_as(:regular) }

  def sql_during
    sqls = []
    callback = ->(*, payload) { sqls << payload[:sql] unless %w[SCHEMA TRANSACTION].include?(payload[:name]) }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
    sqls
  end

  def add_training(name)
    create(:training, name_en: name, name_fr: "#{name} fr").tap do |training|
      create(:learning_module, training: training, level: "Beginner", title: "#{name} b1")
      create(:learning_module, training: training, level: "Beginner", title: "#{name} b2")
      create(:learning_module, training: training, level: "Advanced", title: "#{name} a1")
      create(:learning_module, training: training, level: "Intermediate", title: "#{name} s1", subskill: "Sub")
    end
  end

  def page_text = Nokogiri::HTML(response.body).text.squish

  it "counts completed modules per training and per level, including modules that belong to a subskill" do
    laser = add_training("Laser")
    add_training("Print")
    create(:learning_module_track, :completed, user: user, learning_module: laser.learning_modules.find_by!(title: "Laser b1"))
    create(:learning_module_track, :completed, user: user, learning_module: laser.learning_modules.find_by!(title: "Laser s1"))
    create(:learning_module_track, user: user, learning_module: laser.learning_modules.find_by!(title: "Laser b2"))
    create(:learning_module_track, :completed, user: create(:user, :regular_user), learning_module: laser.learning_modules.find_by!(title: "Laser a1"))

    get learning_area_index_path

    text = page_text
    expect(text.scan("2 of 4 completed").size).to eq(1)
    expect(text.scan("0 of 4 completed").size).to eq(1)
    expect(text).to include("1 / 2 beginner", "0 / 1 advanced", "1 / 1 intermediate", "Beginner 1 of 2 completed", "Advanced 0 of 1 completed")
    expect(text).to include("0 / 2 beginner")
  end

  it "does not count or list a training's modules once per training and level" do
    add_training("Laser")
    get learning_area_index_path
    add_training("Print")
    add_training("Weld")

    per_row = sql_during { get learning_area_index_path }.grep(/COUNT\(\*\)[^"]*"learning_module_tracks"|SELECT "learning_modules"\."level"|SELECT COUNT\(\*\) FROM "learning_modules"/)

    expect(per_row).to be_empty
  end
end
