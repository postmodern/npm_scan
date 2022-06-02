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

require "./email_address"

module NPMScan
  class Package

    record Maintainer, name : String, email : String

    getter name : String

    @hash : Hash(String,JSON::Any)

    def initialize(@name : String, json : JSON::Any)
      @hash = json.as_h

      @maintainers = nil
      @emails      = nil
      @domains     = nil
    end

    @maintainers : Array(Maintainer)?

    def maintainers : Array(Maintainer)
      @maintainers ||= @hash["maintainers"].as_a.map do |maintainer|
        hash = maintainer.as_h

        Maintainer.new(hash["name"].as_s,hash["email"].as_s)
      end
    end

    @emails : Array(String)?

    def emails : Array(String)
      @emails ||= maintainers.map(&.email)
    end

    @domains : Array(String)?

    def domains : Array(String)
      @domains ||= emails.map { |email| EmailAddress.domain_for(email) }
    end

    @unique_domains : Array(String)?

    def unique_domains
      @unique_domains ||= domains.uniq
    end

    def security_hold? : Bool
      @hash["description"].as_s == "Security holding package"
    end

    def is_abandoned? : Bool
      maintainers.empty?
    end

    def is_lonely? : Bool
      unique_domains.size == 1
    end

  end
end
