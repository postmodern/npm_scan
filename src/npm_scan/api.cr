require "http"
require "json"

module NPMScan
  class API
    class RateLimitError < RuntimeError
    end

    ALL_DOCS_URI = "/_all_docs"

    def all_docs
      replicate_npmjs_com.get(ALL_DOCS_URI) do |response|
        retry do
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
          else
            STDERR.puts "ERROR: received #{response.status_code}"
            return
          end
        end
      end
    end

    def package_metadata(package_name : String) : JSON::Any?
      path = "/#{URI.encode_path_segment(package_name)}"

      retry do
        response = replicate_npmjs_com.get(path)

        case response.status_code
        when 200
          body = response.body

          return JSON.parse(body)
        when 429
          raise(RateLimitError.new)
        else
          STDERR.puts "ERROR: #{package_name}: received #{response.status_code}"
          return nil
        end
      end
    end

    def maintainer_emails_for(package_name : String) : Array(String)?
      if (package_metadata = package_metadata(package_name))
        maintainers = package_metadata.as_h["maintainers"].as_a

        return maintainers.map { |maintainer| maintainer.as_h["email"].as_s }
      end
    end

    def download_count(package_name : String) : Int32?
      path = "/downloads/point/last-week/#{URI.encode_path(package_name)}"

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
        else
          STDERR.puts "ERROR: #{package_name}: received #{response.status_code}"
          return nil
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
      rescue RateLimitError
        loop do
          begin
            return yield
          rescue error : RateLimitError
            attempts += 1
            sleep(2**attempts)
          end
        end
      end
    end

  end
end
