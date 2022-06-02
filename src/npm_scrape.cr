#
# npm_scan - Scans npmjs.org for NPM packages that can be taken over.
#
# Copyright (C) 2022 Hal Brodigan
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

require "./npm_scan/api"

require "option_parser"

module NPMScrape
  class CLI

    IGNORED_PACKAGES = Set{"no-one-left-behind"}

    getter workers : Int32

    getter output_dir : String

    getter? recursive

    def initialize
      @workers = 20

      @output_dir = "npmjs"
      @recursive  = false
    end

    def parse_options : Int32
      OptionParser.parse do |parser|
        parser.banner = "usage: npm_downloads [FILE]"

        parser.on("-o","--output DIR","Saves the JSON files to a directory.") do |dir|
          @output_dir = dir
        end

        parser.on("-R","--recursive","Recursively scrape NPM package metadata.") do |dir|
          @recursive = true
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
            output_path = File.join(@output_dir,"#{package_name}.json")

            unless File.file?(output_path)
              begin
                json = api.scrape_package_metadata(package_name)

                scraped_metadata_channel.send({package_name, json})
              rescue error : NPMScan::API::Error
                print_error error.message
              end
            end

            if @recursive
              json = File.read(output_path)
              dependents = parse_dependents(json)

              dependents.each do |dependent|
                unless IGNORED_PACKAGES.includes?(dependent)
                  package_names_channel.send(dependent)
                end
              end
            end
          end

          scraped_metadata_channel.send(nil)
        end
      end

      workers_left = @workers

      while workers_left > 0
        if (package_metadata = scraped_metadata_channel.receive)
          package_name, raw_json = package_metadata

          output_path = File.join(@output_dir,"#{package_name}.json")
          Dir.mkdir_p(File.dirname(output_path))

          puts "Scraped #{package_name} ..."
          File.write(output_path,raw_json)
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

    private def parse_dependents(raw_json : String) : Array(String)
      json = JSON.parse(raw_json)

      return json.as_h["context"].as_h["dependents"].as_h["dependentsTruncated"].as_a.map(&.as_s)
    end

  end
end

NPMScrape::CLI.start
