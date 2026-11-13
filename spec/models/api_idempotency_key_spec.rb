# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApiIdempotencyKey, type: :model do
  describe ".acceptable?" do
    it "accepts a non-blank key of at most 255 characters" do
      expect(described_class.acceptable?(SecureRandom.uuid)).to be(true)
      expect(described_class.acceptable?("k" * 255)).to be(true)
    end

    it "refuses a missing, blank or longer key" do
      [nil, "", "  ", "k" * 256].each { |key| expect(described_class.acceptable?(key)).to be(false) }
    end
  end

  describe ".digest_of" do
    def request_for(body, path: "/api/v1/training_sessions", method: "POST")
      ActionDispatch::Request.new(Rack::MockRequest.env_for(path, method: method, input: body.to_json,
                                                                  "CONTENT_TYPE" => "application/json"))
    end

    it "is the same for the same body with its object keys in another order, nested ones too" do
      one = request_for({ a: 1, b: { c: [1, { d: 2, e: 3 }] } })
      two = request_for({ b: { c: [1, { e: 3, d: 2 }] }, a: 1 })
      expect(described_class.digest_of(one)).to eq(described_class.digest_of(two))
    end

    it "differs when a value, the array order, the path or the method differs" do
      base = described_class.digest_of(request_for({ a: [1, 2] }))
      expect(described_class.digest_of(request_for({ a: [2, 1] }))).not_to eq(base)
      expect(described_class.digest_of(request_for({ a: [1, 3] }))).not_to eq(base)
      expect(described_class.digest_of(request_for({ a: [1, 2] }, path: "/api/v1/other"))).not_to eq(base)
      expect(described_class.digest_of(request_for({ a: [1, 2] }, method: "PUT"))).not_to eq(base)
    end
  end

  describe ".record" do
    let(:user) { create(:user, :staff) }

    it "stores the key with the block's response body and answers true" do
      result = described_class.record(user: user, key: "k1", digest: "d", status: 201) { { id: 5 } }
      expect(result).to be(true)
      row = described_class.find_by!(user: user, key: "k1")
      expect(row).to have_attributes(request_digest: "d", response_status: 201, response_body: { "id" => 5 })
      expect(row.same_request?("d")).to be(true)
      expect(row.same_request?("other")).to be(false)
    end

    it "rolls back what the block wrote and answers false when the key is already recorded" do
      described_class.create!(user: user, key: "k2", request_digest: "d", response_status: 201,
                              response_body: { id: 1 })
      result = described_class.record(user: user, key: "k2", digest: "d", status: 201) do
        CourseName.create!(name: "Rolled back")
        { id: 2 }
      end
      expect(result).to be(false)
      expect(CourseName.where(name: "Rolled back")).to be_empty
      expect(described_class.find_by!(user: user, key: "k2").response_body).to eq("id" => 1)
    end

    it "keeps nothing when the block raises" do
      expect do
        described_class.record(user: user, key: "k3", digest: "d", status: 201) { raise ActiveRecord::RecordInvalid }
      end.to raise_error(ActiveRecord::RecordInvalid)
      expect(described_class.where(key: "k3")).to be_empty
    end
  end
end
