# Copyright (c) 2006, Gennady Bystritsky <bystr@mac.com>
#
# Distributed under the MIT Licence.
# This is free software. See 'LICENSE' for details.
# You must read and accept the license prior to use.

require 'net/ssh'
require 'tsc/errors.rb'
require 'tsc/synchro-queue.rb'

module TSC
  module Session
    class SshStream
      def initialize(host, options)
        @session = Net::SSH::Session.new(host, options)
        @queue = TSC::SynchroQueue.new(true)
        @channel = open

        @session_thread = Thread.new(Thread.current) do |_thread|
          TSC::Error.relay _thread do
            @session.loop
          end
        end
      end

      def get_available_data
        @queue.get or raise EOFError, "Connection to #{@session.host.inspect} closed on remote request"
      end

      def write(data)
        @channel.send_data(data)
      end

      def reset
        @channel.close
      end

      private
      #######

      def open
        @session.open_channel { |_channel|
          _channel.on_success {
            _channel.on_success {
              @connected = true
            }
            _channel.send_request 'shell', nil, true
          }
          _channel.on_failure {
            @connected = false
            raise IOError, "Connection to #{@session.host.inspect} failed"
          }
          _channel.on_data { |_channel, _data|
            @queue.put _data
          }
          _channel.on_extended_data { |_channel, _data|
            @queue.put _data
          }
          _channel.on_eof {
            _channel.close
            @connected = false
            @queue.put nil
          }
          _channel.on_close {
            @connected = false
            @session.close
          }
          _channel.on_window_adjust {
          }
          _channel.request_pty :want_reply => true
        }
      end
    end
  end
end

if $0 == __FILE__ or defined?(Test::Unit::TestCase)
  require 'test/unit'

  module TSC
    module Session
      class SshStreamTest < Test::Unit::TestCase
        def test_nothing
        end

        def setup
        end

        def teardown
        end
      end
    end
  end
end
