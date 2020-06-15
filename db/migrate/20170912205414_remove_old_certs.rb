# frozen_string_literal: true

class RemoveOldCerts < ActiveRecord::Migration[5.0]
  def up
    Certification.where(training_session_id: nil).destroy_all
  end
end
