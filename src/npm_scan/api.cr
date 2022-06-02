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

require "http"
require "json"
require "xml"

module NPMScan
  class API
    class Error < RuntimeError

      # The error message.
      #
      # Note: All API errors must have a message!
      getter! message : String

    end

    class HTTPError < Error
    end

    class InvalidResponse < Error
    end

    class RecoverableError < RuntimeError
    end

    class RateLimitError < RecoverableError
    end

    class TimeoutError < RecoverableError
    end

    ALL_DOCS_PATH = "/_all_docs"

    def all_docs
      retry do
        replicate_npmjs_com.get(ALL_DOCS_PATH) do |response|
          case response.status_code
          when 200
            stream = response.body_io

            # ignore the first line
            stream.gets

            stream.each_line do |line|
              # HACK: instead of parsing each line's JSON, we just do some
              # String-fu to extract the package name string value.
              if (quote_end = line.index('"',7))
                package_name = line[7...quote_end]

                unless package_name.empty?
                  yield package_name
                end
              end
            end
          when 429
            raise(RateLimitError.new)
          when 504, 524
            raise(TimeoutError.new)
          else
            raise(HTTPError.new("unexpected HTTP status (#{response.status_code}) for path: #{ALL_DOCS_PATH}"))
          end
        end
      end
    end

    private def package_metadata(package_name : String) : JSON::Any
      path = "/#{URI.encode_path_segment(package_name)}"

      retry do
        response = replicate_npmjs_com.get(path)

        case response.status_code
        when 200
          unless (body = response.body).empty?
            return JSON.parse(body)
          else
            raise(InvalidResponse.new("received empty response body for path: #{path}"))
          end
        when 429
          raise(RateLimitError.new)
        when 504, 524
          raise(TimeoutError.new)
        else
          raise(HTTPError.new("unexpected HTTP status (#{response.status_code}) for path: #{path}"))
        end
      end
    end

    def get_package(package_name : String) : Package
      Package.new(package_name,package_metadata(package_name))
    end

    enum Period
      DAY = 1
      WEEK = 7
      MONTH = 30

      def path : String
        case self
        in DAY then "last-day"
        in WEEK then "last-week"
        in MONTH then "last-month"
        end
      end
    end

    def scrape_package_metadata(package_name : String) : String
      path = "/package/#{package_name}"

      retry do
        response = npmjs_com.get(path)

        case response.status_code
        when 200
          unless (body = response.body).empty?
            doc = XML.parse_html(body)

            if (script = doc.xpath_node("//script[@integrity]"))
              js = script.inner_text

              if (first_curly_brace = js.index('{'))
                return js[first_curly_brace..]
              else
                raise(InvalidResponse.new("could not find JSON in <script integrity=\"...\"> tag: https://www.npmjs.com#{path}"))
              end
            else
              raise(InvalidResponse.new("could not find the <script integrity=\"...\"> tag in document: https://www.npmjs.com#{path}"))
            end
          else
            raise(InvalidResponse.new("received empty response body for path: #{path}"))
          end
        when 429
          raise(RateLimitError.new)
        when 504, 524
          raise(TimeoutError.new)
        else
          raise(HTTPError.new("unexpected HTTP status (#{response.status_code}) for path: https://www.npmjs.com#{path}"))
        end
      end
    end

    def download_count(package_name : String)
      json = JSON.parse(scrape_package_metadata(package_name))
      hash = json.as_h

      return hash["context"].as_h["downloads"].as_a.last.as_h["downloads"].as_i
    end

    @replicate_npmjs_com : HTTP::Client?

    private def replicate_npmjs_com
      @replicate_npmjs_com ||= HTTP::Client.new("replicate.npmjs.com", tls: true)
    end

    @api_npmjs_org : HTTP::Client?

    private def api_npmjs_org
      @api_npmjs_org ||= HTTP::Client.new("api.npmjs.org", tls: true)
    end

    @npmjs_com : HTTP::Client?

    private def npmjs_com
      @npmjs_com ||= HTTP::Client.new("www.npmjs.com", tls: true)
    end

    private def retry(max_attempts = 10)
      attempts = 0

      begin
        return yield
      rescue RateLimitError | TimeoutError
        loop do
          begin
            return yield
          rescue error : RateLimitError | TimeoutError
            attempts += 1
            sleep(2**attempts)
          end
        end
      end
    end

  end
end
