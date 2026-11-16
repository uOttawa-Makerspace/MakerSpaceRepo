FactoryBot.define do
  factory :staff_space do
    association :user, :staff
    association :space
    color { '#3788d8' }

    # A staff user created with a space is already assigned to it (see the :staff trait), so a
    # staff_space for that pair reuses the assignment and applies the given attributes to it.
    initialize_with { StaffSpace.find_or_initialize_by(user: user, space: space) }
  end
end
