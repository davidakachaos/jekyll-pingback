require_relative "pingback/version"
require_relative "pingback/client"

require "net/http"
require "uri"
require "openssl"

module Jekyll
  module Pingback
  	class << self
      # define simple getters and setters
      attr_reader :config, :jekyll_config, :cache_files, :cache_folder,
                  :file_prefix, :types, :supported_templates, :js_handler
      attr_writer :api_suffix
    end

    @pingback_data_cache = {}
    @logger_prefix = "[jekyll-pingbacks]"

    EXCEPTIONS = [
      SocketError, Timeout::Error,
      Errno::EINVAL, Errno::ECONNRESET, Errno::ECONNREFUSED, EOFError,
      Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError, Net::ProtocolError,
      OpenSSL::SSL::SSLError,
    ].freeze

    def self.bootstrap(site)
      @site = site
      @jekyll_config = site.config
      site.config["pingbacks"] ||= {}
      @config = @jekyll_config["pingbacks"] || {}

      # Set up the cache folder & files
      @cache_folder = site.in_source_dir(@config["cache_folder"] || ".pingbacks-cache")
      Dir.mkdir(@cache_folder) unless File.exist?(@cache_folder)
      @file_prefix = ""
      @file_prefix = "pingbacks_" unless @cache_folder.include? "pingbacks"
      @cache_files = {
        "outgoing" => cache_file("outgoing.yml"),
        "bad_uris" => cache_file("bad_uris.yml"),
        "lookups"  => cache_file("lookups.yml")
      }
      @cache_files.each_value do |file|
        dump_yaml(file) unless File.exist?(file)
      end
    end

    # Helpers
    def self.cache_file(filename)
      Jekyll.sanitized_path(@cache_folder, "#{@file_prefix}#{filename}")
    end

    def self.get_cache_file_path(key)
      @cache_files[key] || false
    end

    def self.read_cached_pingbacks(which)
      return {} unless %w(incoming outgoing).include?(which)

      cache_file = get_cache_file_path which
      load_yaml(cache_file)
    end

    def self.cache_pingbacks(which, webmentions)
      if %w(incoming outgoing).include? which
        cache_file = get_cache_file_path which
        dump_yaml(cache_file, webmentions)

        log "msg", "#{which.capitalize} webmentions have been cached."
      end
    end

    def self.gather_documents(site)
      documents = site.posts.docs.clone

      if @config.dig("pages") == true
        log "info", "Including site pages."
        documents.concat site.pages.clone
      end

      collections = @config.dig("collections")
      if collections
        log "info", "Adding collections."
        site.collections.each do |name, collection|
          # skip _posts
          next if name == "posts"

          unless collections.is_a?(Array) && !collections.include?(name)
            documents.concat collection.docs.clone
          end
        end
      end

      return documents
    end

    def self.log(type, message)
      debug = !!@config.dig("debug")
      if debug || %w(error msg).include?(type)
        type = "info" if type == "msg"
        Jekyll.logger.method(type).call("#{@logger_prefix} #{message}")
      end
    end

    # Utility Method
    # Caches given +data+ to memory and then proceeds to write +data+
    # as YAML string into +file+ path.
    #
    # Returns nothing.
    def self.dump_yaml(file, data = {})
      @pingback_data_cache[file] = data
      File.open(file, "wb") { |f| f.puts YAML.dump(data) }
    end

    # Utility Method
    # Attempts to first load data cached in memory and then proceeds to
    # safely parse given YAML +file+ path and return data.
    #
    # Returns empty hash if parsing fails to return data
    def self.load_yaml(file)
      @pingback_data_cache[file] || SafeYAML.load_file(file) || {}
    end

    # Private Methods

    def self.get_http_response(uri)
      uri  = URI.parse(URI.encode(uri))
      http = Net::HTTP.new(uri.host, uri.port)
      http.read_timeout = 10

      if uri.scheme == "https"
        http.use_ssl = true
        http.ciphers = "ALL:!ADH:!EXPORT:!SSLv2:RC4+RSA:+HIGH:+MEDIUM:-LOW"
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      end

      begin
        request  = Net::HTTP::Get.new(uri.request_uri)
        response = http.request(request)
        return response
      rescue *EXCEPTIONS => e
        log "warn", "Got an error checking #{uri}: #{e}"
        uri_is_not_ok(uri)
        return false
      end
    end

    # Cache bad URLs for a bit
    def self.uri_is_not_ok(uri)
      uri = URI.parse(URI.encode(uri.to_s))
      cache_file = @cache_files["bad_uris"]
      bad_uris = load_yaml(cache_file)
      bad_uris[uri.host] = Time.now.to_s
      dump_yaml(cache_file, bad_uris)
    end

    def self.uri_ok?(uri)
      uri = URI.parse(URI.encode(uri.to_s))
      now = Time.now.to_s
      bad_uris = load_yaml(@cache_files["bad_uris"])
      if bad_uris.key? uri.host
        last_checked = DateTime.parse(bad_uris[uri.host])
        cache_bad_uris_for = @config["cache_bad_uris_for"] || 1 # in days
        recheck_at = last_checked.next_day(cache_bad_uris_for).to_s
        return false if recheck_at > now
      end
      return true
    end

    private_class_method :get_http_response
  end
end
# Load all the bits
def require_all(group)
  Dir[File.expand_path("#{group}/*.rb", __dir__)].each do |file|
    require file
  end
end

require_all "commands"
require_all "generators"