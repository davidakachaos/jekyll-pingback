require 'net/http'
require 'uri'
require 'xmlrpc/client'
require 'nokogiri'

module Jekyll
  module Pingback
    class InvalidTargetException < StandardError
    end
    # This class allows to send pingback requests.
    class Client
      # send an pingback request to the targets associated pingback server.
      #
      # @param [String] source_uri the address of the site containing the link.
      # @param [String] target_uri the target of the link on the source site.
      # @raise [Pingback::InvalidTargetException] raised if the target is not a pingback-enabled resource
      # @raise [XMLRPC::FaultException] raised if the server responds with a faultcode
      # @return [String] message indicating that the request was successful
      def ping(source_uri, target_uri)
        return true if resolve(target_uri) == Net::HTTPNotFound
        header = request_header target_uri
        pingback_server = header['X-Pingback']

        unless pingback_server
          doc = Nokogiri::HTML(request_all(target_uri).body)
          link = doc.xpath('//link[@rel="pingback"]/attribute::href').first
          pingback_server = URI.escape(link.content) if link
        end

        raise InvalidTargetException unless pingback_server

        send_pingback pingback_server, source_uri, target_uri
      end

      private
      def request_header(uri)
        http, res_uri = get_http(uri)
        req = Net::HTTP::Head.new res_uri.path
        http.request req
      end
      
      def request_all(uri)
        http, res_uri = get_http(uri)
        req = Net::HTTP::Get.new res_uri.path
        http.request req
      end

      def get_http(uri)
        resolved_uri = resolve(uri)
        uri  = URI.parse(URI.encode(resolved_uri))
        http = Net::HTTP.new(uri.host, uri.port)
        http.read_timeout = 10

        if uri.scheme == "https"
          http.use_ssl = true
          http.ciphers = "ALL:!ADH:!EXPORT:!SSLv2:RC4+RSA:+HIGH:+MEDIUM:-LOW"
          http.verify_mode = OpenSSL::SSL::VERIFY_PEER
        end
        return http, uri
      end

      def resolve(uri_str, agent = 'curl/7.43.0', max_attempts = 10, timeout = 10)
        attempts = 0
        cookie = nil

        until attempts >= max_attempts
          attempts += 1

          url = URI.parse(uri_str)
          http = Net::HTTP.new(url.host, url.port)
          http.open_timeout = timeout
          http.read_timeout = timeout
          path = url.path
          path = '/' if path == ''
          path += '?' + url.query unless url.query.nil?

          params = { 'User-Agent' => agent, 'Accept' => '*/*' }
          params['Cookie'] = cookie unless cookie.nil?
          request = Net::HTTP::Get.new(path, params)

          if url.instance_of?(URI::HTTPS)
            http.use_ssl = true
            http.verify_mode = OpenSSL::SSL::VERIFY_NONE
          end
          response = http.request(request)

          case response
            when Net::HTTPNotFound then
              # Not found!
              return Net::HTTPNotFound
            when Net::HTTPSuccess then
              break
            when Net::HTTPRedirection then
              location = response['Location']
              cookie = response['Set-Cookie']
              new_uri = URI.parse(location)
              uri_str = if new_uri.relative?
                          url + location
                        else
                          new_uri.to_s
                        end
            else
              raise 'Unexpected response: ' + response.inspect
          end

        end
        raise 'Too many http redirects' if attempts == max_attempts

        uri_str
        # response.body
      end

      def send_pingback(server, source_uri, target_uri)
        server_uri = URI.parse server
        ssl = server_uri.scheme == "https"
        c = XMLRPC::Client.new(server_uri.host, server_uri.path, server_uri.port, nil, nil, nil, nil, ssl)
        if server_uri.scheme == "https"
          c.http.use_ssl = true
          c.http.ciphers = "ALL:!ADH:!EXPORT:!SSLv2:RC4+RSA:+HIGH:+MEDIUM:-LOW"
          c.http.verify_mode = OpenSSL::SSL::VERIFY_PEER
        end
        begin
          c.call('pingback.ping', source_uri, target_uri).inspect
        rescue RuntimeError => e
          puts "Error with url: #{target_uri}"
          return true
        rescue Net::HTTPNotFound
          puts "NOT FOUND: #{target_uri}"
          return true
        rescue => e
          if e.faultCode == 0
            # Error 0 means succes? So don't raise an error
            return true
          else
            puts "Error string: #{e.faultString}"
            puts "Error code: #{e.faultCode}"
            raise e
          end
        end
      end
    end
  end
end