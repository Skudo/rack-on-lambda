# frozen_string_literal: true

module RackOnLambda
  module Adapters
    class RestApi
      attr_reader :context, :event

      def initialize(context:, event:)
        @context = context
        @event = event.deep_stringify_keys
      end

      def env
        @env ||= default_env.merge(env_request_metadata)
                            .merge(env_headers)
                            .merge(env_params)
                            .merge(env_body)
      end

      def response(status, headers, body)
        Responses::RestApiResponse.new(status, headers, body).as_json
      end

      private

      def default_env
        {
          'SCRIPT_NAME' => '',
          'rack.version' => Rack::VERSION,
          'rack.errors' => $stderr,
          'rack.multithread' => true,
          'rack.multiprocess' => true,
          'rack.run_once' => false
        }
      end

      def env_body
        result = event['body'] || ''
        result = Base64.decode64(result) if event['isBase64Encoded']

        {
          'rack.input' => StringIO.new(result).set_encoding(Encoding::BINARY),
          'CONTENT_LENGTH' => result.bytesize.to_s
        }
      end

      def env_headers
        result = {}
        http_headers.each_pair do |header, value|
          key = key_for_header(header)
          result[key] = value.to_s
        end
        result
      end

      def env_params
        {
          'QUERY_STRING' => query_string
        }
      end

      def env_request_metadata
        {
          'REQUEST_METHOD' => event['httpMethod'],
          'PATH_INFO' => path_info,
          'SERVER_NAME' => server_name,
          'SERVER_PORT' => server_port.to_s,
          'rack.url_scheme' => url_scheme
        }
      end

      def http_headers
        event['headers'] || {}
      end

      def key_for_header(header)
        key = header.upcase.tr('-', '_')
        case key
        when 'CONTENT_LENGTH', 'CONTENT_TYPE' then key
        else "HTTP_#{key}"
        end
      end

      def path_info
        event['path'] || ''
      end

      def query_string
        return @query_string if defined?(@query_string)

        query = Query.new
        event['multiValueQueryStringParameters']&.each_pair do |key, value|
          query.add(key, value)
        end
        @query_string = query.to_s
      end

      def server_name
        http_headers['Host'] || 'localhost'
      end

      def server_port
        http_headers['X-Forwarded-Port'] || 443
      end

      def url_scheme
        http_headers['CloudFront-Forwarded-Proto'] ||
          http_headers['X-Forwarded-Proto'] ||
          'https'
      end
    end
  end
end
