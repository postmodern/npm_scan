require "./npm_scan/api"

require "option_parser"

module NPMDownloads
  class CLI

    PERIODS = {
      "day"   => NPMScan::API::Period::DAY,
      "week"  => NPMScan::API::Period::WEEK,
      "month" => NPMScan::API::Period::MONTH
    }

    getter period : NPMScan::API::Period

    getter workers : Int32

    def initialize
      @period  = NPMScan::API::Period::WEEK
      @workers = 20
    end

    def parse_options : Int32
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

      return 0
    end

    def self.start
      exit new().run
    end

    def run : Int32
      parse_options

      package_names_channel = Channel(String?).new

      spawn do
        ARGF.each_line do |line|
          package_name = line.split(/\s+/,2).first

          package_names_channel.send(package_name)
        end

        @workers.times { package_names_channel.send(nil) }
      end

      download_counts_channel = Channel({String,Int32}?).new

      @workers.times do
        spawn name: "API worker" do
          api = NPMScan::API.new

          while (package_name = package_names_channel.receive)
            begin
              download_count = api.download_count(package_name, period: period)

              download_counts_channel.send({package_name, download_count})
            rescue error : NPMScan::API::HTTPError
              print_error error.message
            end
          end

          download_counts_channel.send(nil)
        end
      end

      workers_left = @workers

      while workers_left > 0
        if (download_count = download_counts_channel.receive)
          package_name, count = download_count

          puts "#{package_name}: #{count}"
        else
          workers_left -= 1
        end
      end

      return 0
    end

    @[AlwaysInline]
    private def print_error(message : String)
      STDERR.puts "error: #{message}"
    end

  end
end

NPMDownloads::CLI.start
