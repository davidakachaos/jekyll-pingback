# coding: utf-8
# frozen_string_literal: true

#  (c) Aaron Gustafson
#  https://github.com/aarongustafson/jekyll-webmention_io
#  Licence : MIT
#
#  This generator caches sites you mention so they can be mentioned
#

module Jekyll
  module Pingback
    class QueuePingbacks < Generator
      safe true
      priority :low

      def generate(site)
        @site = site
        @site_url = site.config["url"].to_s

        if @site.config['serving']
          Jekyll::Pingback.log "msg", "Pingbacks lookups are not run when running `jekyll serve`."
          @site.config['pingbacks']['pause_lookups'] = true
          return
        end

        if @site_url.include? "localhost"
          Pingback.log "msg", "Pingbacks lookups are not run on localhost."
          return
        end

        if @site.config.dig("pingbacks", "pause_lookups")
          Pingback.log "info", "Webmention lookups are currently paused."
          return
        end

        Pingback.log "msg", "Beginning to gather pingbacks you’ve made. This may take a while."

        upgrade_outgoing_pingback_cache

        posts = Pingback.gather_documents(@site)

        gather_pingbacks(posts)
      end

      private

      def gather_pingbacks(posts)
        pingbacks = Pingback.read_cached_pingbacks "outgoing"

        posts.each do |post|
          uri = File.join(@site_url, post.url)
          mentions = get_mentioned_uris(post)
          if pingbacks.key? uri
            mentions.each do |mentioned_uri, response|
              unless pingbacks[uri].key? mentioned_uri
                pingbacks[uri][mentioned_uri] = response
              end
            end
          else
            pingbacks[uri] = mentions
          end
        end

        Pingback.cache_pingbacks "outgoing", pingbacks
      end

      def get_mentioned_uris(post)
        uris = {}
        if post.data["pingback"]
          uris[post.data["pingback"]] = false
        end
        return uris
      end

      def upgrade_outgoing_pingback_cache
        old_sent_file = Pingback.cache_file("sent.yml")
        old_outgoing_file = Pingback.cache_file("queued.yml")
        unless File.exist? old_sent_file
          return
        end
        sent_pingbacks = Pingback.load_yaml(old_sent_file)
        outgoing_pingbacks = Pingback.load_yaml(old_outgoing_file)
        merged = {}
        outgoing_pingbacks.each do |source_url, pingbacks|
          collection = {}
          pingbacks.each do |target_url|
            collection[target_url] = if sent_pingbacks.dig(source_url, target_url)
                                       ""
                                     else
                                       false
                                     end
          end
          merged[source_url] = collection
        end
        Pingback.cache_pingbacks "outgoing", merged
        File.delete old_sent_file, old_outgoing_file
        Pingback.log "msg", "Upgraded your sent pingbacks cache."
      end
    end
  end
end
