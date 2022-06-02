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
  class OutputFile < File

    getter path : String

    def self.open(path : String, resume : Bool = false) : OutputFile
      mode = if resume; "a"
             else       "w"
             end

      file = new(path,mode)
      file.flush_on_newline = true
      return file
    end

  end
end
