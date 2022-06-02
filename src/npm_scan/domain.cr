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

require "dns"

module NPMScan
  struct Domain
    RECORD_TYPES = [DNS::RecordType::A, DNS::RecordType::AAAA, DNS::RecordType::MX]

    getter name : String

    def initialize(@name : String)
    end

    def registered?(resolver : DNS::Resolver)
      RECORD_TYPES.any? do |record_type|
        response = resolver.query(@name,record_type)
        !response.answers.empty?
      end
    end

    def ==(other : Domain) : Bool
      @name == other.name
    end

    def to_s : String
      @name
    end

    def to_s(io : IO)
      @name.to_s(io)
    end

  end
end
