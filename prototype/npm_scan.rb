require 'bundler/setup'
require 'async'
require 'async/queue'
require 'async/http/internet'
require 'async/dns'

require 'set'
require 'json'

class Package

  attr_reader :name

  attr_reader :domain

  def initialize(name: , domain: )
    @name = name
    @domain = domain
  end

  def to_s
    @name
  end

end

class RateLimitError < RuntimeError
end

def rate_limit
  attempts = 0

  begin
    yield
  rescue RateLimitError
    attempts += 1
    slee(2 ** attempts)

    retry
  end
end

api_workers = 20
dns_workers = 100

def debug(message)
  $stderr.puts(message) if $DEBUG
end

Async do |parent|
  package_names = Async::LimitedQueue.new(api_workers)

  Async do
    internet = Async::HTTP::Internet.new
    response = internet.get('https://replicate.npmjs.com/_all_docs')

    response.each do |chunk|
      chunk.scan(/"key":"([^"]+)"/) do |match|
        package_name = match[0]

        debug "Package: #{package_name}"
        package_names.enqueue(package_name)
      end
    end

    api_workers.times { package_names << nil }
    internet.close
  end

  lonely_packages = Async::LimitedQueue.new(dns_workers)

  api_workers.times do
    Async do |task|
      internet = Async::HTTP::Internet.new

      while (package_name = package_names.dequeue)
        rate_limit do
          debug "Querying #{package_name} ..."
          response = internet.get("https://replicate.npmjs.com/#{URI.encode_www_form_component(package_name)}")

          case response.status
          when 200
            json = JSON.parse(response.read)

            domains = json['maintainers'].map { |maintainer|
              maintainer['email'].split('@',2).last
            }.uniq

            if (domains.length == 1)
              lonely_packages << Package.new(
                name: package_name,
                domain: domains[0]
              )
            end
          when 429
            raise(RateLimitError.new)
          else
            $stderr.puts "error: #{package_name}: received #{response.status}"
          end
        end
      end

      internet.close
      lonely_packages << nil
    end
  end

  resolved_domains     = Set.new
  unregistered_domains = Set.new
  orphaned_packages = Async::Queue.new

  dns_workers.times do
    Async do
      resolver = Async::DNS::Resolver.new(
        [
          [:udp, '8.8.8.8', 53],
          [:udp, '1.1.1.1', 53]
        ]
      )

      while (package = lonely_packages.dequeue)
        if unregistered_domains.include?(package.domain)
          debug "Orphaned package! #{package}"
          orphaned_packages.enqueue(package)
        elsif !resolved_domains.include?(package.domain)
          debug "Resolving #{package.domain} ..."

          addresses = begin
                        resolver.addresses_for(package.domain)
                      rescue Async::DNS::ResolutionFailure
                        []
                      end

          if addresses.empty?
            debug "Orphaned package! #{package}"
            unregistered_domains << package.name
            orphaned_packages.enqueue(package)
          else
            debug "Valid domain: #{package.domain}"
            resolved_domains << package.domain
          end
        end
      end

      orphaned_packages << nil
    end
  end

  Async do
    while (package = orphaned_packages.dequeue)
      puts "Found orphaned package: #{package} domain: #{package.domain}"
    end
  end
end
