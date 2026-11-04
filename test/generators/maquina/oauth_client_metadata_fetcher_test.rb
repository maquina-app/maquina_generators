require "test_helper"
require "generators/maquina/oauth/oauth_generator"
require "openssl"
require "socket"
require "tempfile"

# The plain-Ruby CIMD fetcher maquina:oauth writes into the app, loaded from
# its template and run for real: refusals are asserted against the code path
# itself, and the network cases against a TLS server on localhost with a
# certificate made here. No mocks.
load File.expand_path("../../../lib/generators/maquina/oauth/templates/app/models/oauth_client/metadata_fetcher.rb", __dir__)

class Maquina::Generators::OauthClientMetadataFetcherTest < ActiveSupport::TestCase
  Fetcher = OauthClient::MetadataFetcher

  # One TLS server for the whole file. Each test sets the handler that answers
  # the next request: it gets the socket after the request headers are read.
  class TlsServer
    attr_reader :port, :ca_file
    attr_accessor :handler

    def initialize
      key = OpenSSL::PKey::EC.generate("prime256v1")
      cert = self_signed(key)
      @ca_file = Tempfile.new(["metadata-fetcher-ca", ".pem"]).tap do |file|
        file.write(cert.to_pem)
        file.flush
      end

      context = OpenSSL::SSL::SSLContext.new
      context.cert = cert
      context.key = key
      tcp = TCPServer.new("127.0.0.1", 0)
      @port = tcp.addr[1]
      @server = OpenSSL::SSL::SSLServer.new(tcp, context)
      @thread = Thread.new { accept_loop }
    end

    private

    def accept_loop
      loop do
        socket = @server.accept
        Thread.new(socket) { |client| serve(client) }
      rescue OpenSSL::SSL::SSLError, SystemCallError, IOError
        # A client that refused the certificate, or hung up mid-handshake.
        next
      end
    end

    def serve(socket)
      path = socket.gets.to_s.split[1]
      while (line = socket.gets) && line != "\r\n"
      end
      handler&.call(socket, path)
    rescue SystemCallError, IOError, OpenSSL::SSL::SSLError
      nil
    ensure
      socket.close rescue nil # standard:disable Style/RescueModifier
    end

    def self_signed(key)
      name = OpenSSL::X509::Name.parse("/CN=localhost")
      cert = OpenSSL::X509::Certificate.new
      cert.version = 2
      cert.serial = 1
      cert.subject = name
      cert.issuer = name
      cert.public_key = key
      cert.not_before = Time.now - 60
      cert.not_after = Time.now + 3600
      extensions = OpenSSL::X509::ExtensionFactory.new
      extensions.subject_certificate = cert
      extensions.issuer_certificate = cert
      cert.add_extension(extensions.create_extension("basicConstraints", "CA:TRUE", true))
      cert.add_extension(extensions.create_extension("keyUsage", "digitalSignature,keyCertSign", true))
      cert.add_extension(extensions.create_extension("subjectAltName", "DNS:localhost,IP:127.0.0.1"))
      cert.add_extension(extensions.create_extension("subjectKeyIdentifier", "hash"))
      cert.sign(key, OpenSSL::Digest.new("SHA256"))
      cert
    end
  end

  SERVER = TlsServer.new

  BLOCKED = %w[0.0.0.0 :: 100.64.0.1 100.127.255.254 127.0.0.1 10.0.0.1 172.16.0.1 192.168.1.1
    169.254.169.254 fe80::1 ::1 fc00::1 fd12:3456::1 ::ffff:127.0.0.1 ::ffff:10.0.0.1].freeze

  setup do
    Fetcher.permitted_addresses = ["127.0.0.1", "::1"]
    SERVER.handler = nil
  end

  teardown do
    Fetcher.permitted_addresses = []
  end

  test "fetches a valid document" do
    respond_with_json(document)

    assert_equal document, fetch
  end

  test "refuses a URL that is not https" do
    assert_refused(/https URL/) { Fetcher.fetch(client_url.sub("https://", "http://"), ca_file: SERVER.ca_file.path) }
    assert_refused(/https URL/) { Fetcher.fetch("ftp://example.com/client.json") }
    assert_refused(/not a URL|https URL/) { Fetcher.fetch("not a url") }
  end

  test "refuses a URL without a path" do
    assert_refused(/path/) { Fetcher.fetch("https://localhost:#{SERVER.port}") }
    assert_refused(/path/) { Fetcher.fetch("https://localhost:#{SERVER.port}/") }
  end

  test "refuses a literal IP host, v4 or v6, however it is spelled" do
    (BLOCKED + %w[93.184.216.34 2606:4700::1111]).each do |address|
      host = address.include?(":") ? "[#{address}]" : address
      assert_refused(/not an IP address/, address) { Fetcher.fetch("https://#{host}/client.json") }
    end
    %w[2130706433 0x7f.0.0.1 127.1].each do |host|
      assert_refused(/not an IP address/, host) { Fetcher.fetch("https://#{host}/client.json") }
    end
  end

  test "blocks loopback, private, link-local, unspecified and carrier-grade NAT addresses" do
    Fetcher.permitted_addresses = []

    BLOCKED.each { |address| assert Fetcher.blocked_address?(address), address }
    %w[93.184.216.34 8.8.8.8 100.128.0.1 2606:4700::1111].each { |address| refute Fetcher.blocked_address?(address), address }
  end

  test "refuses a host that resolves to a loopback address" do
    Fetcher.permitted_addresses = []
    respond_with_json(document)

    assert_refused(/private address/) { fetch }
  end

  test "refuses a host that does not resolve" do
    assert_refused(/does not resolve|private address/) { Fetcher.fetch("https://does-not-exist.invalid/client.json") }
  end

  test "never follows a redirect" do
    SERVER.handler = ->(socket, _path) do
      socket.write "HTTP/1.1 302 Found\r\nLocation: https://localhost:#{SERVER.port}/other.json\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
    end

    assert_refused(/redirect/) { fetch }
  end

  test "refuses an error status" do
    SERVER.handler = ->(socket, _path) { socket.write "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n" }

    assert_refused(/answered 404/) { fetch }
  end

  test "refuses an oversized body, with or without a Content-Length" do
    body = JSON.generate(document.merge("padding" => "x" * Fetcher::MAX_BYTES))

    respond_with_json(body)
    assert_refused(/too large/) { fetch }

    SERVER.handler = ->(socket, _path) do
      socket.write "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nConnection: close\r\n\r\n"
      socket.write body
    end
    assert_refused(/too large/) { fetch }
  end

  test "accepts a body of exactly MAX_BYTES" do
    base = JSON.generate(document.merge("padding" => ""))
    body = JSON.generate(document.merge("padding" => "x" * (Fetcher::MAX_BYTES - base.bytesize)))
    assert_equal Fetcher::MAX_BYTES, body.bytesize

    respond_with_json(body)

    assert_equal document["client_id"], fetch["client_id"]
  end

  test "refuses a slow response" do
    SERVER.handler = ->(socket, _path) do
      # Stalls well past TIMEOUT; the fetcher gives up first.
      sleep Fetcher::TIMEOUT * 3
      socket.write json_response(JSON.generate(document))
    end

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    assert_refused(/too long/) { fetch }
    # One read timeout, not a retry (Net::HTTP retries a GET unless told not to).
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, Fetcher::TIMEOUT * 2
  end

  test "refuses a response that trickles its headers" do
    SERVER.handler = ->(socket, _path) do
      # Each byte arrives well inside the read timeout; the whole exchange
      # does not.
      "HTTP/1.1 200 OK\r\nX-Slow: #{"a" * 20}".each_char do |char|
        socket.write char
        sleep 0.5
      end
    end

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    assert_refused(/too long/) { fetch }
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, Fetcher::TIMEOUT * 2
  end

  test "refuses a certificate it cannot verify" do
    respond_with_json(document)

    assert_refused(/TLS/) { Fetcher.fetch(client_url) }
  end

  test "refuses a body that is not JSON or not an object" do
    respond_with_json("<html>hello</html>")
    assert_refused(/not JSON/) { fetch }

    respond_with_json("[1, 2]")
    assert_refused(/not a JSON object/) { fetch }
  end

  test "refuses a client_id that is not the URL it was fetched from" do
    respond_with_json(document.merge("client_id" => "https://evil.example.com/client.json"))

    assert_refused(/does not match/) { fetch }
  end

  test "refuses a document without redirect_uris" do
    respond_with_json(document.except("redirect_uris"))
    assert_refused(/redirect_uris/) { fetch }

    respond_with_json(document.merge("redirect_uris" => []))
    assert_refused(/redirect_uris/) { fetch }

    respond_with_json(document.merge("redirect_uris" => "http://localhost:6274/oauth/callback"))
    assert_refused(/redirect_uris/) { fetch }

    respond_with_json(document.merge("redirect_uris" => ["/relative"]))
    assert_refused(/redirect_uris/) { fetch }

    %w[javascript:alert(1) data:text/html,hi mailto:a@example.com file:///etc/passwd].each do |uri|
      respond_with_json(document.merge("redirect_uris" => [uri]))
      assert_refused(/redirect_uris/, uri) { fetch }
    end
  end

  test "refuses a document without client_name" do
    respond_with_json(document.except("client_name"))
    assert_refused(/client_name/) { fetch }

    respond_with_json(document.merge("client_name" => " "))
    assert_refused(/client_name/) { fetch }
  end

  test "the test-only seams are empty by default" do
    Fetcher.instance_variable_set(:@permitted_addresses, nil)

    assert_equal [], Fetcher.permitted_addresses
    assert_equal 16_384, Fetcher::MAX_BYTES
    assert_equal 3, Fetcher::TIMEOUT
  end

  private

  def client_url
    "https://localhost:#{SERVER.port}/client.json"
  end

  def document
    {"client_id" => client_url, "client_name" => "MCP Inspector", "redirect_uris" => ["http://localhost:6274/oauth/callback"]}
  end

  def fetch
    Fetcher.fetch(client_url, ca_file: SERVER.ca_file.path)
  end

  def respond_with_json(body)
    body = JSON.generate(body) unless body.is_a?(String)
    SERVER.handler = ->(socket, _path) { socket.write json_response(body) }
  end

  def json_response(body)
    "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}"
  end

  def assert_refused(reason, message = nil, &block)
    error = assert_raises(Fetcher::Refused, message, &block)
    assert_match reason, error.message, message
  end
end
