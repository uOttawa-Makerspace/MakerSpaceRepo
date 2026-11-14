# frozen_string_literal: true

require "rails_helper"

# Each module card on the learning area shows the status of the signed-in user's track for it. The tracks are read
# once for the page, not by a query per module.
RSpec.describe "Learning area module statuses", type: :request do
  let!(:user) { sign_in_as(:regular) }

  def add_modules(training, count, tag = "m")
    Array.new(count) { |i| create(:learning_module, training: training, level: "Beginner", title: "#{training.name_en} #{tag}#{i}") }
  end

  def card_statuses
    Nokogiri::HTML(response.body).css("[data-id]").to_h do |card|
      [card.at_css("h6").text, card.at_css("[role=status]")&.text&.strip]
    end
  end

  it "shows each module's status for the signed-in user only" do
    laser = create(:training, name_en: "Laser")
    done, started, untouched, others = add_modules(laser, 4)
    create(:learning_module_track, :completed, user: user, learning_module: done)
    create(:learning_module_track, user: user, learning_module: started, status: "In progress")
    create(:learning_module_track, :completed, user: create(:user, :regular_user), learning_module: others)

    get learning_area_index_path

    expect(card_statuses).to eq(
      done.title => "Completed", started.title => "In progress", untouched.title => nil, others.title => nil
    )
  end

  def track_queries
    sqls = []
    callback = ->(*, payload) { sqls << payload[:sql] if payload[:sql].include?('FROM "learning_module_tracks"') && !payload[:cached] }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { get learning_area_index_path }
    sqls
  end

  it "does not look up the tracks module by module" do
    laser = create(:training, name_en: "Laser")
    add_modules(laser, 2).each { |learning_module| create(:learning_module_track, user: user, learning_module: learning_module) }
    add_modules(laser, 4, "more").each { |learning_module| create(:learning_module_track, user: user, learning_module: learning_module) }

    expect(track_queries.grep(/"learning_module_id" = \$/)).to be_empty
  end
end
