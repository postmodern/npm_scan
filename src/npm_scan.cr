require "./npm_scan/api"
require "./npm_scan/package"
require "./npm_scan/domain"
require "./npm_scan/orphan"
require "./npm_scan/output_file"

require "dns"
require "retrycr"
require "option_parser"

module NPMScan
  wordlist_path : String? = nil
  output_path : String? = nil
  cache_path : String? = nil

  num_package_workers = 30
  num_dns_workers     = 100

  OptionParser.parse do |parser|
    parser.banner = "usage: npm_scan [options]"

    parser.on("-o","--output FILE","Writes output to file") do |path|
      output_path = path
    end

    parser.on("-c","--cache FILE","Write package names to the cache file") do |path|
      cache_path = path
    end

    parser.on("-W","--wordlist_path FILE","Checks the npm packages in the given wordlist_path") do |path|
      wordlist_path = path
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

  package_names = Channel(String?).new(num_package_workers)
  cache_file = if (path = cache_path)
                 OutputFile.new(path.not_nil!)
               end

  spawn do
    if (path = wordlist_path)
      File.open(path.not_nil!) do |file|
        file.each_line do |line|
          package_name = line.chomp
          package_names.send(package_name)
        end
      end
    else
      api = API.new

      api.all_docs do |package_name|
        if cache_file
          cache_file << package_name
        end

        package_names.send(package_name)
      end
    end

    num_package_workers.times { package_names.send(nil) }
  end

  lonely_packages = Channel(Package?).new

  resolved_domains  = Set(String).new
  orphaned_packages = Channel(Orphaned?).new(num_dns_workers)

  num_package_workers.times do
    spawn do
      api = API.new

      while (package_name = package_names.receive)
        # skip forked packages
        if (emails = api.maintainer_emails_for(package_name))
          domains = emails.map { |email| email.split('@',2).last }
          domains.uniq!

          if domains.size == 1
            lonely_packages.send(
              Package.new(name: package_name, domain: domains[0])
            )
          end
        end
      end

      lonely_packages.send(nil)
    end
  end

  num_dns_workers.times do
    spawn do
      resolver = DNS::Resolver.new

      while (package = lonely_packages.receive)
        unless resolved_domains.includes?(package.domain)
          domain = Domain.new(package.domain)

          retryable(on: IO::TimeoutError, tries: 3) do
            if domain.registered?(resolver)
              resolved_domains << domain.name
            else
              orphaned_packages.send(
                Orphaned.new(package: package, domain: domain)
              )
            end
          end
        end
      end

      orphaned_packages.send(nil)
    end
  end

  output_file = if (path = output_path)
                  OutputFile.new(path.not_nil!)
                end

  while (orphane = orphaned_packages.receive)
    puts "Found orphaned npm package: #{orphane.package.name} domain: #{orphane.domain}"

    if output_file
      output_file << "#{orphane.package.name}\t#{orphane.domain}"
    end
  end
end
