# frozen_string_literal: true

require "rails_helper"

# Rich text attachments: the image preview sits above a caption that names the
# file, so the image itself is decorative.
RSpec.describe "active_storage/blobs/_blob", type: :view do
  it "renders an image attachment with an empty alt above a caption naming the file" do
    blob = ActiveStorage::Blob.create_and_upload!(
      io: File.open(Rails.root.join("spec/support/assets/avatar.png")), filename: "avatar.png", content_type: "image/png"
    )
    render partial: "active_storage/blobs/blob", locals: { blob: blob }
    figure = Nokogiri::HTML(rendered).at_css("figure")
    expect(figure.at_css("img")["alt"]).to eq("")
    expect(figure.at_css("figcaption").text).to include("avatar.png")
  end
end
