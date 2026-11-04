# frozen_string_literal: true

require "rails_helper"

RSpec.describe IcsFetcher do
  before { allow(described_class).to receive(:resolve).and_call_original }

  def resolves(host, *addresses)
    allow(Addrinfo).to receive(:getaddrinfo).with(host, nil, nil, :STREAM).and_return(addresses.map { |a| Addrinfo.ip(a) })
  end

  it "returns the body of a feed on a public address" do
    resolves("cal.test", "93.184.216.34")
    stub_request(:get, "https://cal.test/a.ics").to_return(status: 200, body: "BEGIN:VCALENDAR")
    expect(described_class.get("https://cal.test/a.ics")).to eq("BEGIN:VCALENDAR")
  end

  it "returns nil when the server does not answer with a feed" do
    resolves("cal.test", "93.184.216.34")
    stub_request(:get, "https://cal.test/a.ics").to_return(status: 503)
    expect(described_class.get("https://cal.test/a.ics")).to be_nil
  end

  it "refuses URLs that are not plain http or https" do
    ["file:///etc/passwd", "ftp://cal.test/a.ics", "https://cal.test:8443/a.ics", "https://u:p@cal.test/a.ics", "nope"].each do |url|
      expect { described_class.get(url) }.to raise_error(described_class::Refused), url
    end
  end

  it "refuses private, loopback, link-local and unspecified addresses, written out or reached through a name" do
    %w[127.0.0.1 10.1.2.3 172.16.0.5 192.168.1.1 169.254.169.254 0.0.0.0 100.64.0.1].each do |ip|
      expect { described_class.get("http://#{ip}/a.ics") }.to raise_error(described_class::Refused), ip
    end
    ["[::1]", "[fd00::1]", "[::ffff:127.0.0.1]"].each do |ip|
      expect { described_class.get("http://#{ip}/a.ics") }.to raise_error(described_class::Refused), ip
    end
    resolves("internal.test", "10.0.0.8")
    expect { described_class.get("https://internal.test/a.ics") }.to raise_error(described_class::Refused)
    resolves("mixed.test", "93.184.216.34", "127.0.0.1")
    expect { described_class.get("https://mixed.test/a.ics") }.to raise_error(described_class::Refused)
    expect(a_request(:any, /./)).not_to have_been_made
  end

  it "refuses a host that does not resolve" do
    allow(Addrinfo).to receive(:getaddrinfo).and_raise(SocketError)
    expect { described_class.get("https://gone.test/a.ics") }.to raise_error(described_class::Refused)
  end

  it "checks the target of a redirect too" do
    resolves("cal.test", "93.184.216.34")
    stub_request(:get, "https://cal.test/a.ics").to_return(status: 302, headers: { "Location" => "http://127.0.0.1/secret" })
    expect { described_class.get("https://cal.test/a.ics") }.to raise_error(described_class::Refused)
  end

  it "follows a redirect to a public address, a few times at most" do
    resolves("cal.test", "93.184.216.34")
    stub_request(:get, "https://cal.test/a.ics").to_return(status: 301, headers: { "Location" => "/b.ics" })
    stub_request(:get, "https://cal.test/b.ics").to_return(status: 200, body: "OK")
    expect(described_class.get("https://cal.test/a.ics")).to eq("OK")

    stub_request(:get, "https://cal.test/loop.ics").to_return(status: 302, headers: { "Location" => "/loop.ics" })
    expect(described_class.get("https://cal.test/loop.ics")).to be_nil
  end

  # the connection never goes through a proxy named in the environment, so the checked address is the one used
  it "connects directly even when a proxy is set in the environment" do
    resolves("cal.test", "93.184.216.34")
    stub_request(:get, "https://cal.test/a.ics").to_return(status: 200, body: "OK")
    connections = []
    allow(Net::HTTP).to receive(:new).and_wrap_original { |m, *args| m.call(*args).tap { |http| connections << http } }
    saved = ENV.values_at("http_proxy", "https_proxy")
    begin
      ENV["http_proxy"] = ENV["https_proxy"] = "http://proxy.test:3128"
      expect(described_class.get("https://cal.test/a.ics")).to eq("OK")
    ensure
      ENV["http_proxy"], ENV["https_proxy"] = saved
    end
    expect(connections.map(&:proxy_from_env?)).to eq([false])
  end
end
