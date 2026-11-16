# frozen_string_literal: true

require "rails_helper"

# The admin video list shows each uploaded file of each proficient project and learning module video, with its
# parent's title and link, its processing state and its file name. The files and parents are loaded once for the
# whole list, so the number of queries does not grow with the videos. The counts start at two videos: with one, the
# query cache can hide a repeated read.
RSpec.describe "Admin video list: queries", type: :request do
  include ContentSpecHelpers

  # Each video with its own parent, so no read of one is answered from the query cache.
  def videos!(count)
    Array.new(count) do |i|
      parent = i.even? ? { proficient_project: create(:proficient_project) } : { learning_module: create(:learning_module) }
      create(:video, :with_video, proficient_project: nil, processed: i.zero?, **parent)
    end
  end

  # Each shown file as [parent link text, parent link, state, file name].
  def shown
    Nokogiri::HTML(response.body).css(".col-md-4").map do |card|
      title, state = card.css("h5")
      [title.at_css("a").text, title.at_css("a")["href"], state.text.squish, card.at_css("h9").text]
    end
  end

  def queries_for(path)
    get path
    count_queries { get path }
  end

  before { content_sign_in_as(:admin) }

  it "shows each video file with its parent's title and link, its state and its file name" do
    project_video, module_video = videos!(2)

    get videos_path

    expect(response).to have_http_status(:ok)
    expect(shown).to eq([
      [project_video.proficient_project.title, proficient_project_path(project_video.proficient_project), "Done", "1sec.mp4"],
      [module_video.learning_module.title, learning_area_path(module_video.learning_module.id), "In progress...", "1sec.mp4"]
    ])
  end

  it "lists nothing for videos without files" do
    2.times { create(:video, proficient_project: create(:proficient_project)) }

    get videos_path

    expect(response).to have_http_status(:ok)
    expect(shown).to eq([])
  end

  it "runs the same number of queries for two videos as for five" do
    videos!(2)
    two = queries_for(videos_path)
    videos!(3)
    five = queries_for(videos_path)

    expect(shown.size).to eq(5)
    expect(five).to eq(two)
  end
end
