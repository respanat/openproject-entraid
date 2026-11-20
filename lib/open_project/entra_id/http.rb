# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module OpenProject
  module EntraId
    ##
    # Cliente HTTP mínimo (Net::HTTP) con timeouts cortos y respuesta JSON.
    # Respeta HTTPS_PROXY / https_proxy del entorno.
    module Http
      class Error < OpenProject::EntraId::Error
        attr_reader :status, :body

        def initialize(message, status: nil, body: nil)
          super(message)
          @status = status
          @body = body
        end
      end

      OPEN_TIMEOUT = 5
      READ_TIMEOUT = 10

      module_function

      def get_json(url, headers: {})
        request_json(Net::HTTP::Get, url, headers:)
      end

      def post_form(url, form, headers: {})
        request_json(Net::HTTP::Post, url, headers:) { |req| req.set_form_data(form) }
      end

      def post_json(url, payload, headers: {})
        request_json(Net::HTTP::Post, url, headers: headers.merge("Content-Type" => "application/json")) do |req|
          req.body = JSON.generate(payload)
        end
      end

      def request_json(klass, url, headers: {})
        uri = URI.parse(url)
        raise Error, "Solo se permiten URLs https: #{url}" unless uri.is_a?(URI::HTTPS)

        req = klass.new(uri)
        req["Accept"] = "application/json"
        headers.each { |k, v| req[k] = v }
        yield req if block_given?

        response = Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                                                       open_timeout: OPEN_TIMEOUT,
                                                       read_timeout: READ_TIMEOUT) do |http|
          http.request(req)
        end

        body = parse(response.body)
        unless response.is_a?(Net::HTTPSuccess)
          raise Error.new("HTTP #{response.code} en #{uri.host}#{uri.path}", status: response.code.to_i, body:)
        end

        body
      rescue Timeout::Error, SocketError, SystemCallError, OpenSSL::SSL::SSLError => e
        raise Error, "No se pudo conectar con #{uri&.host}: #{e.class}: #{e.message}"
      end

      def parse(text)
        return {} if text.nil? || text.empty?

        JSON.parse(text)
      rescue JSON::ParserError
        { "raw" => text.to_s[0, 500] }
      end
    end
  end
end
