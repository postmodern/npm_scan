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
  end
end

workers = 100

internet = Async::HTTP::Internet.new
package_names = Async::LimitedQueue.new(workers)
lonely_packages = Async::Queue.new
resolved_domains = Set.new
orphaned_packages = Async::Queue.new

Async do |task|
  task.async do
    response = internet.get('https://replicate.npmjs.com/_all_docs')

    response.each do |chunk|
      chunk.scan(/"key":"([^"]+)"/) do |match|
        package_name = match[0]

        puts "Package: #{package_name}"
        package_names.enqueue(package_name)
      end

      workers.times { package_names << nil }
    end
  end

  workers.times do
    task.async do |subtask|
      while (package_name = package_names.dequeue)
        attempts = 0

        begin
          puts "Querying #{package_name} ..."
          response = internet.get("https://replicate.npmjs.com/#{package_name}")

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
        rescue RateLimitError
          puts "warning: rate limited ..."
          attempts += 1
          subtask.sleep(2**atempts)
          retry
        end
      end

      lonely_packages << nil
    end
  end

  workers.times do
    task.async do
      resolver = Async::DNS::Resolver.new(
        [
          [:udp, '8.8.8.8', 53],
          [:udp, '1.1.1.1', 53]
        ]
      )

      while (package = lonely_packages.dequeue)
        unless resolved_domains.include?(package.domain)
          puts "Resolving #{package.domain} ..."

          if resolver.addresses_for(package.domain).empty?
            puts "Orphaned package! #{package}"
            orphaned_packages.enqueue(package)
          else
            puts "Valid domain: #{package.domain}"
            resolved_domains << package.domain
          end
        end
      end

      orphaned_packages << nil
    end
  end

  task.async do
    while (package = orphaned_packages.dequeue)
      puts "Found orphaned package: #{package} domain: #{package.domain}"
    end
  end
end
