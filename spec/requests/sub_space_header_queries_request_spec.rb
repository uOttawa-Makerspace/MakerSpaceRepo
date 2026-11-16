# frozen_string_literal: true

require "rails_helper"

# The room bookings header lists every space with its rooms. Its queries must not grow with the number of spaces.
RSpec.describe "Room bookings header", type: :request do
  def header_queries_for(space_count)
    space_count.times do
      space = create(:space)
      create(:sub_space, space: space, name: "Room B #{SecureRandom.hex(2)}")
      create(:sub_space, space: space, name: "Room A #{SecureRandom.hex(2)}")
    end
    count_queries { get sub_space_booking_index_path }
  end

  before { sign_in_as(:staff) }

  it "lists single-room spaces as links and multi-room spaces as dropdowns, rooms by name" do
    solo = create(:space, name: "Solo")
    solo_room = create(:sub_space, space: solo, name: "Only Room")
    duo = create(:space, name: "Duo")
    second = create(:sub_space, space: duo, name: "Second")
    first = create(:sub_space, space: duo, name: "First")
    create(:space, name: "Empty")

    get sub_space_booking_index_path

    expect(response.body.scan(/dropdownSpace-\d+/).uniq).to eq(["dropdownSpace-#{duo.id}"])
    expect(response.body).to include(">Only Room</a>", sub_space_booking_index_path(room: solo_room.id))
    expect(response.body.index("First")).to be < response.body.index("Second")
    expect(response.body).to include(sub_space_booking_index_path(room: first.id), sub_space_booking_index_path(room: second.id))
    expect(response.body).not_to include("Empty</a>")
  end

  it "runs the same number of queries for more spaces" do
    get sub_space_booking_index_path
    few = header_queries_for(2)
    many = header_queries_for(4)
    expect(many).to eq(few)
  end
end
