# frozen_string_literal: true

require "ipaddr"
require "net/http"
require "socket"

# Fetches an ICS feed from a URL a person typed in (staff external calendars, a space's calendars). Only http and
# https on their default ports are fetched, and only from public addresses: the host is resolved here, every address
# it resolves to must be public, and the connection is made to the address that was checked. A redirect is followed
# (a few times) only after the same checks on its target.
module IcsFetcher
  class Refused < StandardError; end

  MAX_REDIRECTS = 3
  MAX_BYTES = 5.megabytes
  BLOCKED_RANGES = %w[
    0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12 192.0.0.0/24 192.0.2.0/24
    192.168.0.0/16 198.18.0.0/15 198.51.100.0/24 203.0.113.0/24 224.0.0.0/4 240.0.0.0/4
    ::/128 ::1/128 64:ff9b::/96 100::/64 2001:db8::/32 fc00::/7 fe80::/10 ff00::/8
  ].map { |range| IPAddr.new(range) }.freeze

  # Whether the text is an http(s) URL with a host, on the scheme's default port, without a login in it.
  def self.fetchable_url?(url)
    uri = URI.parse(url.to_s.strip)
    uri.is_a?(URI::HTTP) && uri.host.present? && uri.userinfo.nil? && uri.port == uri.default_port
  rescue URI::InvalidURIError
    false
  end

  # The body of the feed, or nil when the server does not answer with one. Raises Refused for a URL that may not be
  # fetched; network errors are the caller's to rescue.
  def self.get(url, timeout: 10)
    uri = parse(url)
    (MAX_REDIRECTS + 1).times do
      response = request(uri, timeout)
      return read_body(response) if response.is_a?(Net::HTTPSuccess)
      return nil unless response.is_a?(Net::HTTPRedirection) && response["location"].present?

      uri = parse(URI.join(uri, response["location"]).to_s)
    end
    nil
  end

  def self.parse(url)
    raise Refused, "not a fetchable URL" unless fetchable_url?(url)

    URI.parse(url.to_s.strip)
  end
  private_class_method :parse

  def self.request(uri, timeout)
    address = public_address(uri.host)
    http = Net::HTTP.new(uri.host, uri.port, nil) # no proxy: an http_proxy setting must not bypass the checked address
    http.ipaddr = address # connect to the address that was checked, not to a second lookup
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = http.read_timeout = timeout
    http.get(uri.request_uri)
  end
  private_class_method :request

  def self.read_body(response)
    body = response.body.to_s
    raise Refused, "feed too large" if body.bytesize > MAX_BYTES

    body
  end
  private_class_method :read_body

  def self.public_address(host)
    addresses = resolve(host).map { |address| unmap(IPAddr.new(address)) }
    raise Refused, "host does not resolve" if addresses.empty?
    raise Refused, "host is not public" if addresses.any? { |ip| BLOCKED_RANGES.any? { |range| range.include?(ip) } }

    addresses.first.to_s
  end
  private_class_method :public_address

  def self.resolve(host)
    literal = host.delete_prefix("[").delete_suffix("]")
    return [literal] if ip_literal?(literal)

    Addrinfo.getaddrinfo(host, nil, nil, :STREAM).map(&:ip_address).uniq
  rescue SocketError
    []
  end

  def self.ip_literal?(text)
    IPAddr.new(text)
    true
  rescue IPAddr::Error
    false
  end

  def self.unmap(ip)
    ip.ipv4_mapped? ? ip.native : ip
  end
  private_class_method :unmap
end
