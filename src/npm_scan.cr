require "./npm_scan/api"
require "./npm_scan/package"
require "./npm_scan/domain"
require "./npm_scan/orphan"

require "dns"
require "retrycr"
require "option_parser"

module NPMScan
  wordlist : String? = nil

  num_package_workers = 30
  num_dns_workers     = 100

  OptionParser.parse do |parser|
    parser.banner = "usage: npm_scan [options]"

    parser.on("-W","--wordlist FILE","Checks the npm packages in the given wordlist") do |path|
      wordlist = path
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

  spawn do
    if (path = wordlist)
      File.open(path) do |file|
        file.each_line do |line|
          package_names.send(line.chomp)
        end
      end
    else
      api = API.new

      api.all_docs do |package_name|
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

  while (orphane = orphaned_packages.receive)
    puts "Found orphaned npm package: #{orphane.package.name} domain: #{orphane.domain}"
  end
end
