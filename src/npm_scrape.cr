require "./npm_scan/api"

require "option_parser"

module NPMScrape
  class CLI

    getter workers : Int32

    getter output_dir : String

    def initialize
      @workers = 20

      @output_dir = "npmjs"
    end

    def parse_options : Int32
      OptionParser.parse do |parser|
        parser.banner = "usage: npm_downloads [FILE]"

        parser.on("-o","--output DIR","Saves the JSON files to a directory.") do |dir|
          @output_dir = dir
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

      scraped_metadata_channel = Channel({String,String}?).new

      @workers.times do
        spawn name: "Scraper worker" do
          api = NPMScan::API.new

          while (package_name = package_names_channel.receive)
            begin
              json = api.scrape_package_metadata(package_name)

              scraped_metadata_channel.send({package_name, json})
            rescue error : NPMScan::API::HTTPError
              print_error error.message
            end
          end

          scraped_metadata_channel.send(nil)
        end
      end

      workers_left = @workers

      while workers_left > 0
        if (package_metadata = scraped_metadata_channel.receive)
          package_name, json = package_metadata

          output_path = File.join(@output_dir,"#{package_name}.json")
          Dir.mkdir_p(File.dirname(output_path))

          puts "Scraped #{package_name} ..."
          File.write(output_path,json)
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

NPMScrape::CLI.start
