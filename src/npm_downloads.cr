require "./npm_scan/api"

require "option_parser"

module NPMDownloads
  period = NPMScan::API::Period::DAY

  OptionParser.parse do |parser|
    parser.banner = "usage: npm_downloads [FILE]"

    parser.on("-d","--last-day","Download counts for the past day") do
      period = NPMScan::API::Period::DAY
    end

    parser.on("-w","--last-week","Download counts for the past week") do
      period = NPMScan::API::Period::WEEK
    end

    parser.on("-m","--last-month","Download counts for the past day") do
      period = NPMScan::API::Period::MONTH
    end
  end

  input = if ARGV[0]
            File.open(ARGV[0])
          else
            STDIN
          end
  api = NPMScan::API.new

  input.each_line do |line|
    package_name = line.split(/\s+/,2).first

    begin
      download_count = api.download_count(package_name, period: period)

      puts "#{package_name}: #{download_count}/#{period}"
    rescue error : NPMScan::API::HTTPError
      STDERR.puts "error: #{error.message}"
    end
  end
end
