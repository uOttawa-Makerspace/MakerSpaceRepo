# frozen_string_literal: true

require "rails_helper"

RSpec.describe ErrorReporting do
  let(:request_id) { "3f2a9c1e-7b64-4d0e-9a1f-5c8e2b7d4a10" }
  let(:host) do
    request = double("request", request_id: request_id)
    Class.new do
      include ErrorReporting

      define_method(:request) { request }
    end.new
  end

  describe "#error_reference" do
    it "is the first 8 characters of the request id" do
      expect(host.send(:error_reference)).to eq("3f2a9c1e")
    end

    it "is empty without a request id" do
      allow(host.request).to receive(:request_id).and_return(nil)
      expect(host.send(:error_reference)).to eq("")
    end
  end

  describe "#report_unexpected" do
    let(:error) { RuntimeError.new("boom").tap { |e| e.set_backtrace(["app/a.rb:1"]) } }

    it "logs the class, message and reference" do
      allow(Rails.logger).to receive(:error)
      host.send(:report_unexpected, error)
      expect(Rails.logger).to have_received(:error).with(/\A\[3f2a9c1e\] RuntimeError: boom\napp\/a.rb:1/)
    end

    it "reports to Rails.error with the request id, reference and the caller's context" do
      allow(Rails.error).to receive(:report)
      host.send(:report_unexpected, error, source: "test")
      expect(Rails.error).to have_received(:report).with(
        error, handled: true, severity: :error,
               context: { source: "test", request_id: request_id, reference: "3f2a9c1e" }
      )
    end
  end

  describe "#unexpected_error_message" do
    it "includes the reference in English" do
      expect(host.send(:unexpected_error_message)).to include("quote reference 3f2a9c1e")
    end

    it "includes the reference in French" do
      I18n.with_locale(:fr) { expect(host.send(:unexpected_error_message)).to include("la référence 3f2a9c1e") }
    end
  end

  describe "#validation_message" do
    let(:record) do
      User.new.tap(&:valid?)
    end

    it "is the translated prefix followed by the validation messages" do
      allow(I18n).to receive(:t).and_call_original
      allow(I18n).to receive(:t).with("errors.generic.not_found").and_return("Could not save.")
      expect(host.send(:validation_message, record, "errors.generic.not_found"))
        .to eq("Could not save. #{record.errors.full_messages.to_sentence}")
    end

    it "has no trailing space when the record has no errors" do
      allow(I18n).to receive(:t).and_call_original
      allow(I18n).to receive(:t).with("errors.generic.not_found").and_return("Could not save.")
      expect(host.send(:validation_message, User.new, "errors.generic.not_found")).to eq("Could not save.")
    end

    it "adds the messages of related records after the record's own, in one sentence" do
      allow(I18n).to receive(:t).and_call_original
      allow(I18n).to receive(:t).with("errors.generic.not_found").and_return("Could not save.")
      related = User.new.tap { |user| user.errors.add(:base, "Related is wrong") }
      expected = (record.errors.full_messages + ["Related is wrong"]).to_sentence
      expect(host.send(:validation_message, record, "errors.generic.not_found", related))
        .to eq("Could not save. #{expected}")
    end
  end
end
