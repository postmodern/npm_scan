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

module NPMScan
  class DNSCache

    @resolved_domains : Set(String)
    @unresolved_domains : Set(String)

    def initialize
      @resolved_domains   = Set(String).new
      @unresolved_domains = Set(String).new
    end

    def is_resolvable?(domain : String) : Bool
      @resolved_domains.includes?(domain)
    end

    def resolvable!(domain : String)
      @resolved_domains << domain
    end

    def is_unresolvable?(domain : String)
      @unresolved_domains.includes?(domain)
    end

    def unresolvable!(domain : String)
      @unresolved_domains << domain
    end

  end
end
