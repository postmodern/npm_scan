require "./api"
require "./package"
require "./email_address"
require "./domain"
require "./orphaned_package"

require "dns"
require "retrycr"

module NPMScan
  class Scanner

    getter api_workers : Int32

    getter dns_workers : Int32

    getter wordlist : IO?

    getter cache : IO?

    getter? resume

    getter resumed_packages : Set(String)

    def initialize(@api_workers : Int32 = 30,
                   @dns_workers : Int32 = 100,
                   @wordlist : IO? = nil,
                   @cache : IO? = nil,
                   @resume : Bool = false,
                   @resumed_packages : Set(String) = Set(String).new)
    end

    record Error, message : String
    record Alert, message : String

    def scan(&block : (OrphanedPackage | Alert | Error) ->)
      package_names_channel = Channel(String?).new(@api_workers)

      spawn do
        each_package_name do |package_name|
          if !@resume || (@resume && !@resumed_packages.includes?(package_name))
            if (cache = @cache)
              cache.puts package_name
            end

            package_names_channel.send(package_name)
          end
        end

        @api_workers.times { package_names_channel.send(nil) }
      end

      lonely_packages_channel = Channel(Package?).new

      @api_workers.times do
        spawn do
          api = API.new

          while (package_name = package_names_channel.receive)
            begin
              emails  = api.maintainer_emails_for(package_name)
              domains = emails.map { |email| EmailAddress.domain_for(email) }
              domains.uniq!

              case domains.size
              when 1
                package = Package.new(name: package_name, domain: domains[0])

                lonely_packages_channel.send(package)
              when 0
                block.call(Alert.new("package #{package_name} has no maintainers!"))
              end
            rescue error : API::HTTPError
              block.call(Error.new(error.message))
            end
          end

          lonely_packages_channel.send(nil)
        end
      end

      resolved_domains   = Set(String).new
      unresolved_domains = Hash(String,OrphanedPackage).new

      orphaned_packages_channel = Channel(OrphanedPackage?).new(@dns_workers)

      @dns_workers.times do
        spawn do
          resolver = DNS::Resolver.new

          while (package = lonely_packages_channel.receive)
            if (orphan = unresolved_domains[package.domain]?)
              orphaned_packages_channel.send(orphan)
            elsif !resolved_domains.includes?(package.domain)
              domain = Domain.new(package.domain)

              retryable(on: IO::TimeoutError, tries: 3) do
                if domain.registered?(resolver)
                  resolved_domains << domain.name
                else
                  orphan = OrphanedPackage.new(package: package, domain: domain)

                  unresolved_domains[domain.name] = orphan
                  orphaned_packages_channel.send(orphan)
                end
              end
            end
          end

          orphaned_packages_channel.send(nil)
        end
      end

      while (orphan = orphaned_packages_channel.receive)
        block.call(orphan)
      end
    end

    def each_package_name
      if (wordlist = @wordlist)
        wordlist.each_line do |line|
          yield line.chomp
        end
      else
        api = API.new

        api.all_docs do |package_name|
          yield package_name
        end
      end
    end

  end
end
