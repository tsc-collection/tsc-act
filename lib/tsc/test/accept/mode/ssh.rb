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
    host = options['host'] || ARGV.shift or raise 'No host specified'
    user = options['user'] or raise 'No user name specified'

    manager = TSC::Session::SshManager.new(host, user, options['password'], options['prompt'])
    manager.verbose = options['verbose'] || options['interactive']

    thread = manager.session do |_terminal|
      TSC::Test::Accept::Runtime.instance.start _terminal, options
    end

    ensure_thread_completion(thread)
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
