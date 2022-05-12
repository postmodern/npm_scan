require "http"
require "json"

module NPMScan
  class API
    class HTTPError < RuntimeError
    end

    class RateLimitError < HTTPError
    end

    class TimeoutError < HTTPError
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
          when 524
            raise(TimeoutError.new)
          else
            raise(HTTPError.new("unexpected HTTP status (#{response.status_code}) for path: #{ALL_DOCS_PATH}"))
          end
        end
      end
    end

    def package_metadata(package_name : String) : JSON::Any
      path = "/#{URI.encode_path_segment(package_name)}"

      retry do
        response = replicate_npmjs_com.get(path)

        case response.status_code
        when 200
          body = response.body

          return JSON.parse(body)
        when 429
          raise(RateLimitError.new)
        when 524
          raise(TimeoutError.new)
        else
          raise(HTTPError.new("unexpected HTTP status (#{response.status_code}) for path: #{path}"))
        end
      end
    end

    def maintainer_emails_for(package_name : String) : Array(String)
      package_metadata = package_metadata(package_name)
      maintainers      = package_metadata.as_h["maintainers"].as_a

      return maintainers.map { |maintainer| maintainer.as_h["email"].as_s }
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

    def download_count(package_name : String, period : Period = Period::DAY) : Int32
      path = "/downloads/point/#{period.path}/#{URI.encode_path_segment(package_name)}"

      retry do
        response = api_npmjs_org.get(path)

        case response.status_code
        when 200
          body = response.body
          json = JSON.parse(body)
          hash = json.as_h

          return hash["downloads"].as_i
        when 429
          raise(RateLimitError.new)
        when 524
          raise(TimeoutError.new)
        else
          raise(HTTPError.new("unexpected HTTP status (#{response.status_code}) for path: #{path}"))
        end
      end
    end

    private def replicate_npmjs_com
      @replicate_npmjs_com ||= HTTP::Client.new("replicate.npmjs.com", tls: true)
    end

    private def api_npmjs_org
      @api_npmjs_org ||= HTTP::Client.new("api.npmjs.org", tls: true)
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
