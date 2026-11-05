# frozen_string_literal: true

module Api
  module V1
    # Public contacts with opening hours (replaces the broken GET /hours JSON).
    # Contract: doc/api/v1/contact_infos.md.
    class ContactInfosController < BaseController
      def index
        contacts = ContactInfo.where(show_hours: true).includes(:opening_hours).order(:name, :id)
        render json: contacts.map { |c| ContactInfoSerializer.call(c) }
      end
    end
  end
end
