# frozen_string_literal: true

# Retired in mid-2025 (the code was removed in chunk 20a, 2026-10: the Google
# Calendar sync, the colour helpers and every caller). The shifts table and its
# rows are kept, and it has foreign keys to spaces and trainings, so this bare
# record class stays only so Space/Training can clear their shifts on destroy.
# Do not add behavior here.
class Shift < ApplicationRecord
  # Cleanup only: removes shifts_users join rows when a shift is destroyed.
  has_and_belongs_to_many :users
end
