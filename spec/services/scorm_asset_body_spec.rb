require "rails_helper"

RSpec.describe ScormAssetBody do
  let(:blob) { instance_double(ActiveStorage::Blob, id: 7) }
  let(:slice) { ScormAssetBody::SLICE }

  def serve(body)
    [].tap { |chunks| body.each { |c| chunks << c } }
  end

  describe ".open" do
    it "reads the first slice itself, then yields the rest of the range in slices of at most 1 MB" do
      allow(blob).to receive(:download_chunk) { |r| "b" * r.size }
      body = described_class.open(blob, 100..(100 + 2 * slice + 9))
      expect(blob).to have_received(:download_chunk).once.with(100..(100 + slice - 1))
      expect(serve(body).map(&:bytesize)).to eq([slice, slice, 10])
      expect(blob).to have_received(:download_chunk).with((100 + slice)..(100 + 2 * slice - 1))
      expect(blob).to have_received(:download_chunk).with((100 + 2 * slice)..(100 + 2 * slice + 9))
    end

    it "reads a short range in one slice" do
      allow(blob).to receive(:download_chunk) { |r| "b" * r.size }
      expect(serve(described_class.open(blob, 3..5)).map(&:bytesize)).to eq([3])
    end

    it "lets a storage error on the first slice reach the caller" do
      allow(blob).to receive(:download_chunk).and_raise(ActiveStorage::FileNotFoundError)
      expect { described_class.open(blob, 0..9) }.to raise_error(ActiveStorage::FileNotFoundError)
    end

    it "raises when the first slice is shorter than requested" do
      allow(blob).to receive(:download_chunk).and_return("abc")
      expect { described_class.open(blob, 0..9) }.to raise_error(ScormAssetBody::ShortRead)
    end
  end

  describe "#each" do
    let(:body) { described_class.new(blob, 0..(2 * slice - 1), "a" * slice) }

    it "logs, reports and raises a storage error on a later slice, after the first slice was sent" do
      allow(blob).to receive(:download_chunk).and_raise(ActiveStorage::FileNotFoundError)
      allow(Rails.logger).to receive(:error)
      allow(Rails.error).to receive(:report)
      seen = []
      expect { body.each { |c| seen << c } }.to raise_error(ActiveStorage::FileNotFoundError)
      expect(seen.size).to eq(1)
      expect(Rails.logger).to have_received(:error).with(/ActiveStorage::FileNotFoundError.*7/)
      expect(Rails.error).to have_received(:report)
        .with(instance_of(ActiveStorage::FileNotFoundError), handled: false, context: { blob_id: 7 })
    end

    it "raises, and never resumes, when a later slice comes back short" do
      allow(blob).to receive(:download_chunk).and_return("short")
      allow(Rails.error).to receive(:report)
      expect { body.each { |_| } }.to raise_error(ScormAssetBody::ShortRead)
      expect(blob).to have_received(:download_chunk).once
    end

    it "passes an error from the consumer (the client side) through, neither logged nor reported" do
      connection_error = defined?(Puma::ConnectionError) ? Puma::ConnectionError : stub_const("Puma::ConnectionError", Class.new(StandardError))
      allow(blob).to receive(:download_chunk).and_return("b" * slice)
      allow(Rails.logger).to receive(:error)
      allow(Rails.error).to receive(:report)
      expect { body.each { raise connection_error } }.to raise_error(connection_error)
      expect(Rails.logger).not_to have_received(:error)
      expect(Rails.error).not_to have_received(:report)
    end
  end
end
