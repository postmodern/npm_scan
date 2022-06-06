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

require "./api"
require "./package"
require "./email_address"
require "./domain"
require "./dns_cache"

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

    record LockedPackage, name : String
    record LonelyPackage, name : String, domain : String
    record OrphanedPackage, name : String, domain : String
    record Error, message : String

    def scan(&block : (LockedPackage | OrphanedPackage | Error) ->)
      package_names_channel = Channel(String?).new(@api_workers)

      spawn name: "package list worker" do
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

      lonely_packages_channel = Channel(LonelyPackage?).new

      @api_workers.times do
        spawn name: "API worker" do
          api = API.new

          while (package_name = package_names_channel.receive)
            begin
              package = api.get_package(package_name)

              if package.is_locked?
                block.call(LockedPackage.new(name: package_name))
              elsif package.is_lonely?
                lonely_packages_channel.send(
                  LonelyPackage.new(
                    name:   package.name,
                    domain: package.unique_domains[0]
                  )
                )
              end
            rescue error : API::Error
              block.call(Error.new(error.message))
            end
          end

          lonely_packages_channel.send(nil)
        end
      end

      api_workers_left = @api_workers

      dns_cache = DNSCache.new
      orphaned_packages_channel = Channel(OrphanedPackage?).new(@dns_workers)

      @dns_workers.times do
        spawn name: "DNS worker" do
          resolver = DNS::Resolver.new

          while api_workers_left > 0
            if (lonely_package = lonely_packages_channel.receive)
              if dns_cache.is_unresolvable?(lonely_package.domain)
                orphaned_packages_channel.send(
                  OrphanedPackage.new(
                    name:   lonely_package.name,
                    domain: lonely_package.domain
                  )
                )
              elsif !dns_cache.is_resolvable?(lonely_package.domain)
                domain = Domain.new(lonely_package.domain)

                retryable(on: IO::TimeoutError, tries: 3) do
                  if domain.registered?(resolver)
                    dns_cache.resolvable!(domain.name)
                  else
                    dns_cache.unresolvable!(domain.name)

                    orphaned_package = OrphanedPackage.new(
                      name:   lonely_package.name,
                      domain: lonely_package.domain
                    )

                    orphaned_packages_channel.send(orphaned_package)
                  end
                end
              end
            else
              api_workers_left -= 1
            end
          end

          orphaned_packages_channel.send(nil)
        end
      end

      dns_workers_left = @dns_workers

      while dns_workers_left > 0
        if (orphaned_package = orphaned_packages_channel.receive)
          block.call(orphaned_package)
        else
          dns_workers_left -= 1
        end
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
