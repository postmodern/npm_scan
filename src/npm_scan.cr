require "./npm_scan/api"
require "./npm_scan/package"
require "./npm_scan/email_address"
require "./npm_scan/domain"
require "./npm_scan/orphaned_package"
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

    def parse_options
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
          unless File.file?(path)
            STDERR.puts "error: no such file: #{path}"
            exit 1
          end

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
          STDERR.puts "error: unknown option: #{flag}"
          STDERR.puts parser
          exit 1
        end
      end

      if @resume && @cache_path.nil?
        STDERR.puts "error: --resume requires the --cache option"
        exit 1
      end
    end

    def self.start
      new().run
    end

    def run
      parse_options

      if @resume && @cache_path
        if File.file?(@cache_path.not_nil!)
          File.open(@cache_path.not_nil!) do |file|
            file.each_line do |line|
              @resumed_packages << line.chomp
            end
          end
        end
      end

      package_names = Channel(String?).new(@num_api_workers)
      cache_file    = if @cache_path
                        OutputFile.new(@cache_path.not_nil!, resume: @resume)
                      end

      spawn do
        if @wordlist_path
          File.open(@wordlist_path.not_nil!) do |file|
            file.each_line do |line|
              package_name = line.chomp

              if !@resume || (@resume && !@resumed_packages.includes?(package_name))
                if cache_file
                  cache_file << package_name
                end

                package_names.send(package_name)
              end
            end
          end
        else
          api = API.new

          api.all_docs do |package_name|
            if !@resume || (@resume && !@resumed_packages.includes?(package_name))
              if cache_file
                cache_file << package_name
              end

              package_names.send(package_name)
            end
          end
        end

        num_api_workers.times { package_names.send(nil) }
      end

      lonely_packages = Channel(Package?).new

      @num_api_workers.times do
        spawn do
          api = API.new

          while (package_name = package_names.receive)
            # skip forked packages
            begin
              emails  = api.maintainer_emails_for(package_name)
              domains = emails.map { |email| EmailAddress.domain_for(email) }
              domains.uniq!

              case domains.size
              when 1
                lonely_packages.send(
                  Package.new(name: package_name, domain: domains[0])
                )
              when 0
                STDERR.puts "alert: package #{package_name} has no maintainers!"
              end
            rescue error : API::HTTPError
              STDERR.puts "error: #{error.message}"
            end
          end

          lonely_packages.send(nil)
        end
      end

      resolved_domains   = Set(String).new
      unresolved_domains = Hash(String,OrphanedPackage).new
      orphaned_packages  = Channel(OrphanedPackage?).new(@num_dns_workers)

      @num_dns_workers.times do
        spawn do
          resolver = DNS::Resolver.new

          while (package = lonely_packages.receive)
            if (orphan = unresolved_domains[package.domain]?)
              orphaned_packages.send(orphan)
            elsif !resolved_domains.includes?(package.domain)
              domain = Domain.new(package.domain)

              retryable(on: IO::TimeoutError, tries: 3) do
                if domain.registered?(resolver)
                  resolved_domains << domain.name
                else
                  orphan = OrphanedPackage.new(package: package, domain: domain)

                  unresolved_domains[domain.name] = orphan
                  orphaned_packages.send(orphan)
                end
              end
            end
          end

          orphaned_packages.send(nil)
        end
      end

      output_file = if @output_path
                      OutputFile.new(@output_path.not_nil!, resume: @resume)
                    end

      while (orphan = orphaned_packages.receive)
        puts "Found orphaned npm package: #{orphan.package.name} domain: #{orphan.domain}"

        if output_file
          output_file << "#{orphan.package.name}\t#{orphan.domain}"
        end
      end

    end
  end
end

NPMScan::CLI.start
