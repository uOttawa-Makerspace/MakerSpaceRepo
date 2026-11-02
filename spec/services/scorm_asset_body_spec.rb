require "rails_helper"

RSpec.describe ScormAssetBody do
  let(:blob) { instance_double(ActiveStorage::Blob, id: 7) }
  let(:slice) { ScormAssetBody::SLICE }

  it "yields the first slice, then the rest of the range in slices of at most 1 MB" do
    first = "a" * slice
    allow(blob).to receive(:download_chunk) { |r| "b" * r.size }
    body = described_class.new(blob, 100..(100 + 2 * slice + 9), first)
    chunks = []
    body.each { |c| chunks << c }
    expect(chunks.map(&:bytesize)).to eq([slice, slice, 10])
    expect(blob).to have_received(:download_chunk).with((100 + slice)..(100 + 2 * slice - 1))
    expect(blob).to have_received(:download_chunk).with((100 + 2 * slice)..(100 + 2 * slice + 9))
  end

  it "lets a failure on a later slice raise instead of turning it into a response" do
    allow(blob).to receive(:download_chunk).and_raise(ActiveStorage::FileNotFoundError)
    allow(Rails.logger).to receive(:error)
    body = described_class.new(blob, 0..(2 * slice - 1), "a" * slice)
    seen = []
    expect { body.each { |c| seen << c } }.to raise_error(ActiveStorage::FileNotFoundError)
    expect(seen.size).to eq(1)
    expect(Rails.logger).to have_received(:error).with(/ActiveStorage::FileNotFoundError.*7/)
  end

  it "does not log a client disconnect, but still raises it" do
    allow(blob).to receive(:download_chunk).and_return("b")
    allow(Rails.logger).to receive(:error)
    body = described_class.new(blob, 0..(2 * slice - 1), "a" * slice)
    expect { body.each { raise Errno::EPIPE } }.to raise_error(Errno::EPIPE)
    expect(Rails.logger).not_to have_received(:error)
  end
end
