# frozen_string_literal: true

require "rails_helper"

# /project_kits lists the viewer's kits with each kit's project, and for an admin every kit with its project and
# holder. Those are loaded once for each list, so the number of queries does not grow with the number of kits. The
# counts start at two kits: with one, the query cache can hide a repeated read.
RSpec.describe "Project kits: queries", type: :request do
  include ContentSpecHelpers

  # Each kit with its own project (and holder), so no read of one is answered from the query cache.
  def kits!(count, user: nil)
    Array.new(count) do
      create(:project_kit, user: user || create(:user, :regular_user),
                           proficient_project: create(:proficient_project, :with_kit))
    end
  end

  def queries_for(path)
    get path
    count_queries { get path }
  end

  def rows(table)
    Nokogiri::HTML(response.body).css("table")[table].css("tbody tr").map { |row| row.css("td").map { |td| td.text.squish } }
  end

  def own_row(kit) = [kit.proficient_project.title, kit.created_at.strftime("%Y/%m/%d"), "Not yet delivered"]

  it "shows a member each of their kits with its project" do
    member = create(:user, :regular_user)
    mine = kits!(2, user: member)
    kits!(1)
    content_login!(member)

    get project_kits_path

    expect(response).to have_http_status(:ok)
    expect(rows(0)).to match_array(mine.map { |kit| own_row(kit) })
  end

  it "shows an admin every kit with its holder and project" do
    content_sign_in_as(:admin)
    kits = kits!(2)

    get project_kits_path

    expect(rows(-1).map { |cells| cells.first(4) })
      .to match_array(kits.map { |kit| [kit.user.name, *own_row(kit)] })
  end

  it "runs the same number of queries for a member's two kits as for five" do
    member = create(:user, :regular_user)
    content_login!(member)
    kits!(2, user: member)
    two = queries_for(project_kits_path)
    kits!(3, user: member)
    five = queries_for(project_kits_path)

    expect(rows(0).size).to eq(5)
    expect(five).to eq(two)
  end

  it "runs the same number of queries for an admin's two kits among two as for five" do
    admin = content_sign_in_as(:admin)
    kits!(1, user: admin)
    kits!(1)
    two = queries_for(project_kits_path)
    kits!(1, user: admin)
    kits!(2)
    five = queries_for(project_kits_path)

    expect(rows(-1).size).to eq(5)
    expect(five).to eq(two)
  end
end
