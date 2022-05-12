require "./npm_scan/api"

require "option_parser"

module NPMDownloads
  PERIODS = {
    "day"   => NPMScan::API::Period::DAY,
    "week"  => NPMScan::API::Period::WEEK,
    "month" => NPMScan::API::Period::MONTH
  }

  period  = NPMScan::API::Period::WEEK
  workers = 20

  OptionParser.parse do |parser|
    parser.banner = "usage: npm_downloads [FILE]"

    parser.on("-p","--period [day|week|month]","Downloads within the the time window. (Default: week)") do |str|
      period = PERIODS.fetch(str) do
                 STDERR.puts "error: unknown --period value: #{str}"
                 exit 1
               end
    end

    parser.on("-w","--workers NUM","The number of concurrent workers.") do |num|
      workers = num.to_i32
    end
  end

  package_names = Channel(String?).new

  spawn do
    input = ARGF

    input.each_line do |line|
      package_name = line.split(/\s+/,2).first

      package_names.send(package_name)
    end

    workers.times { package_names.send(nil) }
  end

  download_counts = Channel({String,Int32}?).new

  workers.times do
    spawn do
      api = NPMScan::API.new

      while (package_name = package_names.receive)
        begin
          download_count = api.download_count(package_name, period: period)

          download_counts.send({package_name, download_count})
        rescue error : NPMScan::API::HTTPError
          STDERR.puts "error: #{error.message}"
        end
      end

      download_counts.send(nil)
    end
  end

  while (download_count = download_counts.receive)
    package_name, count = download_count

    puts "#{package_name}: #{count}"
  end
end
