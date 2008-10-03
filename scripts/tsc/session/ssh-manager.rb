# Copyright (c) 2006, Gennady Bystritsky <bystr@mac.com>
# 
# Distributed under the MIT Licence.
# This is free software. See 'LICENSE' for details.
# You must read and accept the license prior to use.

require 'tsc/session/manager.rb'
require 'tsc/session/ssh-stream.rb'
require 'tsc/session/emulator-provider.rb'

module TSC
  module Session
    class SshManager < TSC::Session::Manager
      include EmulatorProvider

      def initialize(host, user = nil, password = nil, prompt = nil)
        super SshStream.new(host, :password => password), prompt
      end

      def session(&block)
        activate do |_terminal|
          fix_terminal_type
          block.call _terminal if block
        end
      end
    end
  end
end

if $0 == __FILE__ or defined?(Test::Unit::TestCase)
  require 'test/unit'
  
  module TSC
    module Session
      class SshManagerTest < Test::Unit::TestCase
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
