# frozen_string_literal: true
require 'pingback'
module Jekyll
  module Pingback
    module Commands
      	class Pingback < Command
          def self.init_with_program(prog)
            prog.command(:pingback) do |c|
              c.syntax "pingback"
              c.description "Sends queued pingbacks"

              c.action { |args, options| process args, options }
            end
          end
          def self.process(_args = [], options = {})
            options = configuration_from_options(options)
            Jekyll::Pingback.bootstrap(Jekyll::Site.new(options))

            if File.exist? Jekyll::Pingback.cache_file("sent.yml")
              Jekyll::Pingback.log "error", "Your outgoing pingbacks queue needs to be upgraded. Please re-build your project."
            end

            Jekyll::Pingback.log "msg", "Getting ready to send pingbacks (this may take a while)."

            count = 0
            cached_outgoing = Jekyll::Pingback.get_cache_file_path "outgoing"
            if File.exist?(cached_outgoing)
              ping_client = Jekyll::Pingback::Client.new
              outgoing = Jekyll::Pingback.load_yaml(cached_outgoing)
              outgoing.each do |source, targets|
                next if targets == false
                targets.each do |target, response|
                  # skip ones we’ve handled
                  next unless response == false
                  Jekyll::Pingback.log("msg", "Preparing #{target}")

                  # convert protocol-less links
                  if target.index("//").zero?
                    target = "http:#{target}"
                  end

                  # skip bad URLs
                  next unless Jekyll::Pingback.uri_ok?(target)

                  Jekyll::Pingback.log("msg", "Pinging #{target}")

                  # capture JSON responses in case site wants to do anything with them
                  begin
                    ping_client.ping(source, target)
                    response = "Success"
                  rescue Jekyll::Pingback::InvalidTargetException
                    Jekyll::Pingback.log("err", "Could not send pingback to #{target}")
                    Jekyll::Pingback.uri_is_not_ok(target)
                    next
                  end
                  Jekyll::Pingback.log("msg", "Send a pingback to #{target}")
                  outgoing[source][target] = response
                  count += 1
                end
              end
              if count.positive?
                Jekyll::Pingback.dump_yaml(cached_outgoing, outgoing)
              end
              Jekyll::Pingback.log "msg", "#{count} pingbacks sent."
            end # file exists (outgoing)
          end # def process
        end # PingbackCommand
    end # Commands
  end #Pingback
end # Jekyll