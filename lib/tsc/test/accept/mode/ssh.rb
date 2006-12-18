# Copyright (c) 2006, Gennady Bystritsky <bystr@mac.com>
# 
# Distributed under the MIT Licence.
# This is free software. See 'LICENSE' for details.
# You must read and accept the license prior to use.

require 'tsc/test/accept/runner.rb'
require 'tsc/test/accept/runtime.rb'
require 'tsc/session/ssh-manager.rb'

class Runner < TSC::Test::Accept::Runner
  def start
    @manager = TSC::Session::SshManager.new

    host = options['host'] || ARGV.shift or raise 'No host specified'
    user = options['user'] or raise 'No user name specified'
    password = options['password']
    prompt = Regexp.new(options['prompt'] || "[$%#>]\s+$")

    thread = @manager.session(host, user, password) do |_terminal|
      _terminal.screen.lock do
        sleep 5
        _terminal.typein "TERM='#{_terminal.term}' export TERM\n"
        _terminal.screen.wait_prompt prompt, 10
      end
      TSC::Test::Accept::Runtime.instance.start _terminal, options
    end

    ensure_thread_completion thread
  end
end

if $0 == __FILE__ or defined?(Test::Unit::TestCase)
  require 'test/unit'
  
  class SshTest < Test::Unit::TestCase
    def setup
    end
    
    def teardown
    end
  end
end
