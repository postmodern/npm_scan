require "./npm_scan/api"

require "option_parser"

module NPMDownloads
  class CLI

    getter workers : Int32

    getter output_path : String?

    def initialize
      @workers = 20

      @output_path  = nil
    end

    def parse_options : Int32
      OptionParser.parse do |parser|
        parser.banner = "usage: npm_downloads [FILE]"

        parser.on("-o","--output FILE","Writes the output to a file.") do |path|
          @output_path = path
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

      output_file = if (path = @output_path)
                      File.new(path,"w")
                    end

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
              download_count = api.download_count(package_name)

              download_counts_channel.send({package_name, download_count})
            rescue error : NPMScan::API::Error
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
          output_file.puts "#{package_name} #{count}" if output_file
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
