require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"
require "rubygems/package"
require "zlib"
require "stringio"

class UnpackBundleTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)

  def archive(entries)
    io = StringIO.new("".b)
    Zlib::GzipWriter.wrap(io) do |gzip|
      entries.each do |name, body, type, link|
        body ||= ""
        gzip.write Gem::Package::TarHeader.new(name: name, prefix: "", mode: 0o644,
          size: body.bytesize, typeflag: type || "0", linkname: link || "").to_s
        gzip.write body
        gzip.write "\0" * ((512 - body.bytesize % 512) % 512)
      end
      gzip.write "\0" * 1024
    end
    io.string
  end

  def test_rejects_malicious_archives_before_extraction
    bad_storage = [
      [["../escape", "bad"]], [["/absolute", "bad"]],
      [["link", "", "2", "/tmp"]], [["hard", "", "1", "../escape"]],
      [["pipe", "", "6"]]
    ]
    cases = bad_storage.map do |entries|
      [["metadata", "format=ai_lms_clone_v1\n"], ["database.dump", "PGDMP"],
       ["storage.tar.gz", archive(entries)]]
    end
    cases << [["metadata", "", "2", "/tmp/escape"], ["database.dump", "PGDMP"], ["storage.tar.gz", "x"]]
    cases << [["metadata", "format=ai_lms_clone_v1\n"], ["metadata", "duplicate"],
              ["database.dump", "PGDMP"], ["storage.tar.gz", "x"]]
    cases.each do |entries|
      Dir.mktmpdir do |work|
        FileUtils.mkdir_p("#{work}/extracted")
        File.binwrite("#{work}/bundle.tar.gz", archive(entries))
        _, _, status = Open3.capture3({ "bundle" => "#{work}/bundle.tar.gz", "work_dir" => "#{work}/extracted" },
          "bash", "-euo", "pipefail", "-c", 'source "$1"', "bash", "#{ROOT}/deploy/unpack-bundle")
        refute status.success?, entries.inspect
        refute File.exist?("#{work}/escape")
        refute File.symlink?("#{work}/extracted/metadata")
      end
    end
  end
end
