# vim: set sw=2:
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
require 'tsc/session/exec-stream.rb'
require 'tsc/session/emulator-provider.rb'

module TSC
  module Session
    class ExecManager < Manager
      include EmulatorProvider

      def protocol
        :exec
      end

      def session(*command, &block)
        stream = ExecStream.new {
          ENV['TERM'] = emulator.term
          exec *command
        }
        process stream, &block
      end
    end
  end
end

if $0 == __FILE__ or defined?(Test::Unit::TestCase)
  require 'test/unit'

  module TSC
    module Session
      class ExecManagerTest < Test::Unit::TestCase
        def test_session
          message = "Hello, world !!!"
          @terminal = @manager.exec_session("echo #{message.inspect}")
          @terminal.screen.lock {
            @terminal.start
            @terminal.screen.wait_full_update {
              assert_equal message, @terminal.screen.lines.first.strip
            }
          }
        end

        def test_finished
          @terminal = @manager.exec_session "date"
          assert_equal false, @terminal.finished?
          @terminal.start
          assert_nothing_raised do
            timeout 1 do
              until @terminal.finished?
              end
            end
          end
          assert_nothing_raised do
            timeout 1 do
              while @terminal.stream.alive?
              end
            end
          end
          assert_equal true, @terminal.stream.exited?
          assert_equal 0, @terminal.stream.status
        end

        def test_reset
          @terminal = @manager.exec_session "sh"
          @terminal.start
          sleep 1
          assert_equal false, @terminal.finished?
          assert_equal true, @terminal.stream.alive?
          @terminal.reset
          assert_equal true, @terminal.finished?
          assert_nothing_raised do
            timeout 2 do
              while @terminal.stream.alive?
              end
            end
          end
          assert_equal true, (!@terminal.stream.killed? or @terminal.stream.signal != 9)
        end

        def test_detached_session
          result = nil
          timeout 3 do
            thread = @manager.exec_session "sh" do |_terminal|
              @terminal = _terminal
              _terminal.screen.lock {
                _terminal.typein "echo $TERM\n"
                _terminal.screen.wait_full_update {
                  result = _terminal.screen.lines[1]
                }
              }
            end
            thread.join
          end
          assert_match %r{dumb\s*$}, result
          assert_equal true, @terminal.finished?
          timeout 1 do
            while @terminal.stream.alive?
            end
          end
          assert_equal true, (!@terminal.stream.killed? or @terminal.stream.signal != 9)
        end

        def setup
          @terminal = nil
          @manager = Manager.new self
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
