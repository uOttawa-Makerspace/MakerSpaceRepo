# frozen_string_literal: true

class RepoFile < ApplicationRecord
  belongs_to :repository
  belongs_to :proficient_project

  has_one_attached :file
end
