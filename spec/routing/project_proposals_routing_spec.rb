# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Project proposal routes", type: :routing do
  it "keeps the dot of a slug in the id for show, edit and update" do
    expect(get: "/project_proposals/12.after-edit").to route_to("project_proposals#show", id: "12.after-edit")
    expect(get: "/project_proposals/12.after-edit/edit").to route_to("project_proposals#edit", id: "12.after-edit")
    expect(patch: "/project_proposals/12.after-edit").to route_to("project_proposals#update", id: "12.after-edit")
    expect(delete: "/project_proposals/12.after-edit").to route_to("project_proposals#destroy", id: "12.after-edit")
  end

  it "reads a trailing json or js as the response format" do
    expect(get: "/project_proposals/12.json").to route_to("project_proposals#show", id: "12", format: "json")
    expect(get: "/project_proposals/12.after-edit.json").to route_to("project_proposals#show", id: "12.after-edit", format: "json")
    expect(get: "/project_proposals.js").to route_to("project_proposals#index", format: "js")
  end

  it "keeps the collection routes ahead of the id route" do
    expect(get: "/project_proposals/projects_assigned").to route_to("project_proposals#projects_assigned")
    expect(get: "/project_proposals/new").to route_to("project_proposals#new")
    expect(post: "/project_proposals/approve").to route_to("project_proposals#approve")
  end

  it "routes the canonical id-title form" do
    expect(get: "/project_proposals/12-after-edit").to route_to("project_proposals#show", id: "12-after-edit")
    expect(get: "/project_proposals/12-after-edit/edit").to route_to("project_proposals#edit", id: "12-after-edit")
    expect(get: "/project_proposals/12-after-edit.json").to route_to("project_proposals#show", id: "12-after-edit", format: "json")
  end

  it "builds paths from the id or a given param" do
    expect(project_proposal_path("12.after-edit")).to eq("/project_proposals/12.after-edit")
    expect(project_proposal_path(12, format: :json)).to eq("/project_proposals/12.json")
    expect(edit_project_proposal_path("12-after-edit")).to eq("/project_proposals/12-after-edit/edit")
  end
end
