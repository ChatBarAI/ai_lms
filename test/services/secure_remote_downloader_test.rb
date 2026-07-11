require "test_helper"

class SecureRemoteDownloaderTest < ActiveSupport::TestCase
  FakeResponse = Struct.new(:headers, :chunks) do
    def [](name)
      headers[name]
    end

    def read_body
      chunks.each { |chunk| yield chunk }
    end
  end

  test "accepts a public HTTPS destination" do
    downloader = build_downloader([ "93.184.216.34" ])

    assert_equal [ "93.184.216.34" ], downloader.send(:validate_uri!, URI("https://example.com/video.mp4"))
  end

  test "rejects HTTP destinations" do
    downloader = build_downloader([ "93.184.216.34" ])

    error = assert_raises(SecureRemoteDownloader::Error) do
      downloader.send(:validate_uri!, URI("http://example.com/video.mp4"))
    end
    assert_match "HTTPS", error.message
  end

  test "rejects credentials embedded in a URL" do
    downloader = build_downloader([ "93.184.216.34" ])

    assert_raises(SecureRemoteDownloader::Error) do
      downloader.send(:validate_uri!, URI("https://user:secret@example.com/video.mp4"))
    end
  end

  test "enforces an optional exact hostname allowlist" do
    downloader = SecureRemoteDownloader.new(
      allowed_hosts: [ "cdn.example.com" ],
      resolver: ->(_host) { [ "93.184.216.34" ] }
    )

    assert_equal [ "93.184.216.34" ], downloader.send(:validate_uri!, URI("https://cdn.example.com/video.mp4"))
    assert_raises(SecureRemoteDownloader::Error) do
      downloader.send(:validate_uri!, URI("https://attacker.example/video.mp4"))
    end
  end

  test "rejects private loopback link-local and reserved destinations" do
    %w[127.0.0.1 10.1.2.3 169.254.169.254 192.168.1.2 ::1 fe80::1 2001:db8::1].each do |address|
      downloader = build_downloader([ address ])

      assert_raises(SecureRemoteDownloader::Error, "expected #{address} to be rejected") do
        downloader.send(:validate_uri!, URI("https://unsafe.example/video.mp4"))
      end
    end
  end

  test "rejects a hostname if any resolved address is unsafe" do
    downloader = build_downloader([ "93.184.216.34", "127.0.0.1" ])

    assert_raises(SecureRemoteDownloader::Error) do
      downloader.send(:validate_uri!, URI("https://mixed.example/video.mp4"))
    end
  end

  test "revalidates a redirect destination" do
    resolver = lambda do |host|
      host == "public.example" ? [ "93.184.216.34" ] : [ "169.254.169.254" ]
    end
    downloader = SecureRemoteDownloader.new(resolver: resolver)
    redirect = Net::HTTPFound.new("1.1", "302", "Found")
    redirect["Location"] = "https://metadata.internal/latest/meta-data"

    request_stub = ->(*_args, &block) { block.call(redirect) }
    downloader.stub(:perform_request, request_stub) do
      assert_raises(SecureRemoteDownloader::Error) do
        downloader.download("https://public.example/video", tempfile_prefix: "test") { |_file| flunk }
      end
    end
  end

  test "rejects a declared body larger than the byte limit" do
    downloader = SecureRemoteDownloader.new(max_bytes: 5)
    response = FakeResponse.new({ "Content-Length" => "6", "Content-Type" => "video/mp4" }, [])

    Tempfile.create("bounded-download") do |file|
      assert_raises(SecureRemoteDownloader::Error) do
        downloader.send(:write_response!, response, file)
      end
    end
  end

  test "stops a streamed body when it crosses the byte limit" do
    downloader = SecureRemoteDownloader.new(max_bytes: 5)
    response = FakeResponse.new({ "Content-Type" => "video/mp4" }, [ "123", "456" ])

    Tempfile.create("bounded-download") do |file|
      assert_raises(SecureRemoteDownloader::Error) do
        downloader.send(:write_response!, response, file)
      end
      assert_operator file.size, :<=, 5
    end
  end

  test "rejects a non-video response content type" do
    downloader = SecureRemoteDownloader.new(max_bytes: 100)
    response = FakeResponse.new({ "Content-Type" => "text/html" }, [ "<html>" ])

    Tempfile.create("bounded-download") do |file|
      assert_raises(SecureRemoteDownloader::Error) do
        downloader.send(:write_response!, response, file)
      end
    end
  end

  test "accepts MP4 WebM and Ogg signatures" do
    downloader = SecureRemoteDownloader.new
    signatures = [
      "\x00\x00\x00\x18ftypisom".b,
      "\x1A\x45\xDF\xA3webm".b,
      "OggSvideo".b
    ]

    signatures.each do |signature|
      Tempfile.create("video-signature", binmode: true) do |file|
        file.write(signature)
        file.rewind
        assert_nil downloader.send(:validate_video_signature!, file)
      end
    end
  end

  test "rejects content without a supported video signature" do
    downloader = SecureRemoteDownloader.new

    Tempfile.create("video-signature", binmode: true) do |file|
      file.write("<html>not a video</html>")
      file.rewind
      assert_raises(SecureRemoteDownloader::Error) do
        downloader.send(:validate_video_signature!, file)
      end
    end
  end

  test "private HTTP destinations require both explicit development overrides" do
    downloader = SecureRemoteDownloader.new(
      allow_private_network: true,
      allow_http: true,
      resolver: ->(_host) { [ "127.0.0.1" ] }
    )

    assert_equal [ "127.0.0.1" ], downloader.send(:validate_uri!, URI("http://localhost:4567/video"))
  end

  private

  def build_downloader(addresses)
    SecureRemoteDownloader.new(resolver: ->(_host) { addresses })
  end
end
