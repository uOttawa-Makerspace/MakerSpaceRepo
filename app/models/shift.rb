# frozen_string_literal: true

# Retired in mid-2025 (chunk 20a removed the Google Calendar sync, the colour
# helpers and every caller). The shifts table and its rows are kept, and it has
# foreign keys to spaces and trainings, so this bare record class stays only so
# Space/Training can clear their shifts on destroy. Do not add behavior here.
class Shift < ApplicationRecord
end
