=begin
 
             Tone Software Corporation BSD License ("License")
  
                        Acceptance Testing Framework
  
  Please read this License carefully before downloading this software. By
  downloading or using this software, you are agreeing to be bound by the
  terms of this License. If you do not or cannot agree to the terms of
  this License, please do not download or use the software.
  
  Provides facility for creating custom test suites for
  acceptance/regression testing. The engine allows interfacing a system to
  be tested through a variety of means such as a process on a local host
  via a PTY (pseudo terminal), a network host via TELNET, an MVS host via
  3270 protocol, etc. An internal screen image for the system under test
  is constantly maintained, with ability to examine it and to handle
  various events. Input to the system under test can be generated with
  support for functional keys. Ruby test/unit framework is readily
  available for assertions.
       
  Copyright (c) 2003, 2004, Tone Software Corporation
       
  All rights reserved.
       
  Redistribution and use in source and binary forms, with or without
  modification, are permitted provided that the following conditions are
  met:
    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer. 
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution. 
    * Neither the name of the Tone Software Corporation nor the names of
      its contributors may be used to endorse or promote products derived
      from this software without specific prior written permission. 
  
  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS
  IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
  TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
  PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER
  OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
  EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
  PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
  PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
  LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
  NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
  SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
  
=end

require 'tsc/session/manager.rb'
require 'tsc/session/telnet-stream.rb'
require 'tsc/session/emulator-provider.rb'

module TSC
  module Session
    class TelnetManager < Manager
      include EmulatorProvider

      def session(host, user = nil, password = nil, prompt = nil, &block)
        host_array = host.to_s.split ':'
        host = host_array[0].strip
        port = host_array[1].to_i

        options = Hash[
          'Host' => host, 
          'Port' => (port==0 ? 23 : port)
        ]
        options['Prompt'] = prompt if prompt

        stream = TelnetStream.new options

        user_array = user.to_s.split ':'
        user = user_array[0].to_s.strip
        password ||= user_array[1]

        stream.login user, password.to_s.strip unless user.empty?
        process stream, &block
      end
    end
  end
end

if $0 == __FILE__ or defined?(Test::Unit::TestCase)
  require 'test/unit'
  
  module TSC
    module Session
      class TelnetManagerTest < Test::Unit::TestCase
        def test_session
          @terminal = @manager.session("localhost:7")
          @terminal.start
          @terminal.screen.lock {
            @terminal.typein "abcdef\n"
            @terminal.screen.wait_full_update {
              assert_equal "abcdef", @terminal.screen.lines.first.strip
            }
          }
        end

        def setup
          @terminal = nil
          @manager = TelnetManager.new
        end

        def teardown
          @terminal.reset if @terminal
          @manager = nil
          @terminal = nil
        end
      end
    end
  end
end
