# frozen_string_literal: true

require "rails_helper"

# Chunk 16: MakesController. A "make" is a Repository row whose make_id points
# at the original (there is no Make model). This is also where the repository's
# GitHub columns are copied; no GitHub HTTP call is made anywhere in the flow.
#
# Gates: `signed_in`; the original is looked up by (owner username, id) via
# Repository's default_scope, so soft-deleted originals are not found.
RSpec.describe "Makes (HTTP contract)", type: :request do
  include ContentSpecHelpers

  let(:owner) { create(:user, :regular_user) }
  let(:maker) { create(:user, :regular_user) }
  let!(:original) do
    create(:repository, owner: owner, title: "Original Thing", users: [owner],
                        license: "Creative Commons - Attribution", github: true,
                        github_url: "https://github.com/x/y")
  end

  def make_params(title: "My Make", description: "built it", image: content_png_upload)
    # The param root is the ORIGINAL repository's title (params.require(@repository.title)).
    { original.title => { title: title, description: description,
                          photos_attributes: { "0" => { image: image } } } }
  end

  describe "GET new" do
    it "sends a guest to login" do
      get makes_new_path(owner.username, original.id)
      expect(response.location).to include("/login")
    end

    it "renders for a signed-in user" do
      content_login!(maker)
      get makes_new_path(owner.username, original.id)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Original Thing")
    end

    it "500s when the username does not own the id (set_repository returns nil) (D-C21)" do
      content_login!(maker)
      # WART(D-C21): find_by returns nil and the action dereferences it; should be a 404
      get makes_new_path("somebody-else", original.id)
      expect(response).to have_http_status(:internal_server_error)
    end

    it "500s for a soft-deleted original" do
      original.update_columns(deleted: true)
      content_login!(maker)
      get makes_new_path(owner.username, original.id)
      expect(response).to have_http_status(:internal_server_error)
    end
  end

  describe "POST create" do
    it "sends a guest to login and creates nothing" do
      expect { post makes_create_path(owner.username, original.id), params: make_params }
        .not_to change(Repository, :count)
    end

    it "creates a public child repository owned by the maker, +15 reputation, original make counter +1" do
      content_login!(maker)
      expect { post makes_create_path(owner.username, original.id), params: make_params }
        .to change(Repository, :count).by(1)
      made = Repository.find_by(title: "My Make")
      expect(made.make_id).to eq(original.id)
      expect(made.parent).to eq(original)
      expect(made.user_id).to eq(maker.id)
      expect(made.share_type).to eq("public")
      expect(made.license).to eq("Creative Commons - Attribution")
      expect(made.github).to eq("t")
      expect(made.github_url).to eq("https://github.com/x/y")
      expect(made.photos.count).to eq(1)
      expect(original.reload.make).to eq(1)
      expect(maker.reload.reputation).to eq(15)
      expect(response).to redirect_to("/#{maker.username}/#{made.slug}")
      expect(original.makes).to eq([made])
    end

    it "does not add the maker to the make's members (users stays empty) (D-C22)" do
      content_login!(maker)
      post makes_create_path(owner.username, original.id), params: make_params
      # WART(D-C22): maker is user_id but not in repository.users, so check_ownership denies them edit/delete of their own make (see D-C07)
      expect(Repository.find_by(title: "My Make").users).to be_empty
    end

    it "copies categories and equipment from the original" do
      Category.create!(name: "Laser", repository_id: original.id)
      Equipment.create!(name: "Cutter", repository_id: original.id)
      content_login!(maker)
      post makes_create_path(owner.username, original.id), params: make_params
      made = Repository.find_by(title: "My Make")
      expect(made.categories.pluck(:name)).to eq(["Laser"])
      expect(made.equipments.pluck(:name)).to eq(["Cutter"])
    end

    it "500s when no photos_attributes are sent (nested attributes got nil) (D-C24)" do
      content_login!(maker)
      params = { original.title => { title: "No Photo", description: "x" } }
      expect { post makes_create_path(owner.username, original.id), params: params }
        .not_to change(Repository, :count)
      # WART(D-C24): photos_attributes = nil raises ArgumentError instead of a validation error
      expect(response).to have_http_status(:internal_server_error)
    end

    it "an invalid make (blank title) re-renders new with 200 and an alert" do
      content_login!(maker)
      expect { post makes_create_path(owner.username, original.id), params: make_params(title: "") }
        .not_to change(Repository, :count)
      expect(response).to have_http_status(:ok)
      expect(flash[:alert]).to eq("Something went wrong")
      expect(original.reload.make).to eq(0)
    end

    it "rejects a non-image photo" do
      content_login!(maker)
      expect do
        post makes_create_path(owner.username, original.id), params: make_params(image: content_stl_upload)
      end.not_to change(Repository, :count)
    end

    it "redirects with the parameter_missing alert when the title-keyed root is absent" do
      content_login!(maker)
      post makes_create_path(owner.username, original.id), params: { repository: { title: "x" } }
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to include("Original Thing")
    end

    it "lets a maker make a private repository without its password (D-C23)" do
      secret = create(:repository, :private, owner: owner, title: "Hush", users: [owner])
      content_login!(maker)
      # WART(D-C23): no check_auth on makes#new/create; the private original's data is copied to a public child
      post makes_create_path(owner.username, secret.id),
           params: { secret.title => { title: "Leak", description: "d", photos_attributes: { "0" => { image: content_png_upload } } } }
      expect(Repository.find_by(title: "Leak").share_type).to eq("public")
    end
  end
end
