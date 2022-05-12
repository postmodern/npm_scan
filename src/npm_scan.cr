require "./npm_scan/scanner"
require "./npm_scan/output_file"

require "dns"
require "retrycr"
require "option_parser"

module NPMScan
  class CLI

    getter wordlist_path : String?
    getter output_path : String?
    getter cache_path : String?
    getter? resume
    getter resumed_packages : Set(String)

    getter num_api_workers : Int32
    getter num_dns_workers : Int32

    def initialize
      @num_api_workers = 30
      @num_dns_workers = 100

      @wordlist_path = nil
      @output_path   = nil
      @cache_path    = nil

      @resume = false
      @resumed_packages = Set(String).new
    end

    def parse_options : Int32
      OptionParser.parse do |parser|
        parser.banner = "usage: npm_scan [options]"

        parser.on("-o","--output FILE","Writes output to file") do |path|
          @output_path = path
        end

        parser.on("-c","--cache FILE","Write package names to the cache file") do |path|
          @cache_path = path
        end

        parser.on("-R","--resume","Skips package already in the --cache file") do
          @resume = true
        end

        parser.on("-W","--wordlist-path FILE","Checks the npm packages in the given wordlist_path") do |path|
          @wordlist_path = path
        end

        parser.on("-A","--api-workers NUM","Number of API request workers (Default: #{num_api_workers})") do |num|
          @num_api_workers = num.to_i32
        end

        parser.on("-D","--dns-workers NUM","Number of DNS request workers (Default: #{num_dns_workers})") do |num|
          @num_dns_workers = num.to_i32
        end

        parser.on("-h","--help","Prints this cruft") do
          puts parser
          exit 0
        end

        parser.invalid_option do |flag|
          print_error "unknown option: #{flag}"
          STDERR.puts parser
          exit 1
        end
      end

      if @wordlist_path && !File.file?(@wordlist_path.not_nil!)
        print_error "no such file: #{@wordlist_path}"
        return 1
      end

      if @resume && @cache_path.nil?
        print_error "--resume requires the --cache option"
        return 1
      end

      return 0
    end

    def self.start
      exit new().run
    end

    def run : Int32
      unless (ret = parse_options)
        return ret
      end

      if @resume && @cache_path
        if File.file?(@cache_path.not_nil!)
          File.open(@cache_path.not_nil!) do |file|
            file.each_line do |line|
              @resumed_packages << line.chomp
            end
          end
        end
      end

      cache_file = if @cache_path
                     OutputFile.open(@cache_path.not_nil!, resume: @resume)
                   end

      wordlist_file = if @wordlist_path
                        File.open(@wordlist_path.not_nil!)
                      end

      output_file = if @output_path
                      OutputFile.open(@output_path.not_nil!, resume: @resume)
                    end

      scanner = Scanner.new(
        api_workers: @num_api_workers,
        dns_workers: @num_dns_workers,

        wordlist: wordlist_file,
        cache:    cache_file,

        resume:           @resume,
        resumed_packages: resumed_packages
      )

      scanner.scan do |result|
        case result
        in OrphanedPackage

          puts "Found orphaned npm package: #{result.package.name} domain: #{result.domain}"

          if output_file
            output_file.puts "#{result.package.name}\t#{result.domain}"
          end
        in Scanner::Alert
          print_alert result.message
        in Scanner::Error
          print_alert result.message
        end
      end

      return 0
    end

    @[AlwaysInline]
    private def print_error(message)
      STDERR.puts "error: #{message}"
    end

    @[AlwaysInline]
    private def print_alert(message)
      STDERR.puts "alert: #{message}"
    end

  end
end

NPMScan::CLI.start
