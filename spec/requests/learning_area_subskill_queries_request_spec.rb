# frozen_string_literal: true

require "rails_helper"

# The subskill page lists every module of a subskill with its photos, video and project files. Those attachments are
# loaded once for the whole list, so the number of attachment queries does not grow with the number of modules.
RSpec.describe "Learning area subskill page attachments", type: :request do
  let!(:user) { sign_in_as(:regular) }
  let(:training) { create(:training) }

  def sql_during
    sqls = []
    callback = ->(*, payload) { sqls << payload[:sql] unless %w[SCHEMA TRANSACTION].include?(payload[:name]) }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
    sqls
  end

  def asset(name, type)
    Rack::Test::UploadedFile.new(Rails.root.join("spec/support/assets", name), type)
  end

  def add_module(title)
    create(:learning_module, training: training, title: title, subskill: "welding").tap do |learning_module|
      learning_module.photos.attach([asset("avatar.png", "image/png"), asset("test.png", "image/png")])
      learning_module.videos.attach(asset("1sec.mp4", "video/mp4"))
      learning_module.project_files.attach(asset("RepoFile1.pdf", "application/pdf"))
    end
  end

  def attachment_queries
    sqls = sql_during { get subskill_learning_area_index_path("welding") }
    expect(response).to have_http_status(:ok)
    sqls.grep(/FROM "active_storage_(attachments|blobs)"/)
  end

  def page = Nokogiri::HTML(response.body)

  it "shows each module's photos, video and project files next to a SCORM module" do
    %w[Alpha Beta Gamma].each { |title| add_module(title) }
    create(:learning_module, :with_scorm_object, training: training, title: "Packaged", subskill: "welding")

    get subskill_learning_area_index_path("welding")

    expect(response).to have_http_status(:ok)
    expect(page.css("video").size).to eq(3)
    expect(page.css("img[alt='Alpha'], img[alt='Beta'], img[alt='Gamma']").size).to eq(3)
    expect(page.css("img[alt='Gallery photo']").size).to eq(6)
    expect(page.css("a").map(&:text).count("RepoFile1.pdf")).to eq(3)
    expect(page.css("#scorm-processing-container").size).to eq(1)
  end

  it "does not query attachments once per module" do
    add_module("Alpha")
    one_module = attachment_queries.size
    add_module("Beta")
    add_module("Gamma")

    expect(attachment_queries.size).to eq(one_module)
  end

  it "loads no attachments of a SCORM module that it does not show" do
    create(:learning_module, :with_scorm_object, training: training, title: "Packaged", subskill: "welding")
    create(:learning_module, :with_scorm_object, training: training, title: "Packaged two", subskill: "welding")

    get subskill_learning_area_index_path("welding")

    expect(response).to have_http_status(:ok)
    expect(page.css("#scorm-processing-container").size).to eq(2)
  end
end
