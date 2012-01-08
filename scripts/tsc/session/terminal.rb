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

require 'forwardable'
require 'tsc/synchro-queue.rb'
require 'tsc/errors.rb'

module TSC
  module Session
    class Terminal
      class TerminalError < RuntimeError
        def initialize
          super "Terminal not operatable"
        end
      end

      extend Forwardable

      attr_reader :stream, :emulator
      attr_reader :data_read_thread, :screen_update_thread, :screen_check_thread
      def_delegators :@data_queue, :high_water_mark
      def_delegators :@emulator, :screen, :term

      def initialize(stream, emulator)
        @error_handler_thread = Thread.current

        @stream = stream
        @emulator = emulator
        @emulator.screen.newline_assumes_return = true

        @finished = false

        @data_queue = allocate_blocking_synchro_queue
        @data_read_thread = nil
        @screen_update_thread = nil
        @screen_check_thread = nil
      end

      def finished?
        @finished
      end

      def start
        raise TerminalError if @finished == true

        start_data_thread
        start_update_thread

        @data_read_thread.priority = 10
      end

      def stop
        @data_read_thread = stop_thread @data_read_thread
        @screen_update_thread = stop_thread @screen_update_thread
        stop_screen_check
      end

      def reset
        stop
        @stream.reset
        @finished = true
      end

      def stop_screen_check
        @screen_check_thread = stop_thread @screen_check_thread
      end

      def start_screen_check(destination = $stderr)
        raise TerminalError if @finished == true
        stop_screen_check
        @screen_check_thread ||= Thread.new do
          TSC::Error.relay @error_handler_thread do
            loop do
              screen.wait_update do
                screen.show destination
              end
            end
          end
        end
        @screen_check_thread.priority = -5
      end

      def typein(*keys)
        raise TerminalError if @finished == true
        keys.each do |_key|
          @stream.write @emulator.key_sequence(_key)
        end
      end

      private
      #######
      def allocate_blocking_synchro_queue
        SynchroQueue.new true
      end

      def start_data_thread
        @data_read_thread ||= Thread.new(Thread.current) do |_master|
          begin
            loop do
              @data_queue.put(@stream.get_available_data || break)
            end
          rescue Exception => exception
            _master.raise exception
          end
          @finished = true
          @data_read_thread = nil
        end
      end

      def start_update_thread
        @screen_update_thread ||= Thread.new do
          TSC::Error.relay @error_handler_thread do
            loop do
              @emulator.process_data @data_queue.get
            end
          end
        end
      end

      def stop_thread(thread)
        thread.kill unless thread.nil?
        nil
      end
    end
  end
end

if $0 == __FILE__ or defined? Test::Unit::TestCase
  require 'timeout'
  require 'test/unit'
  require 'tsc/session/key.rb'
  require 'tsc/session/dumb-emulator.rb'
  require 'tsc/session/screen.rb'

  module TSC
    module Session
      class TerminalTest < Test::Unit::TestCase
        class MockStream
          attr_reader :incoming

          def initialize
            @outgoing = SynchroQueue.new true
            @incoming = []
            @reset = false
          end

          def reset
            @reset = true
          end

          def reset?
            @reset
          end

          def get_available_data
            @outgoing.get
          end

          def write(*args)
            @incoming.concat args
          end

          def data(*args)
            @outgoing.put *args
          end
        end

        def test_display
          with_data "abcdef" do
            assert_equal "abcdef", @terminal.screen.lines[0].strip
          end
        end

        def test_high_water_mark
          assert_equal 0, @terminal.high_water_mark

          with_data "abcdef" do
            assert_equal 1, @terminal.high_water_mark
          end

          with_locked_screen_and_data "abcdef", "zzzzzz" do
            assert_equal 2, @terminal.high_water_mark
          end

          with_locked_screen_and_data "abcdef", "zzzzzz" do
            assert_equal 2, @terminal.high_water_mark
          end

          with_locked_screen_and_data "abcdef", "zzzzzz", "bbbbb" do
            assert_equal 3, @terminal.high_water_mark
          end
        end

        def test_typein_string
          @terminal.typein "abcdef"
          assert_equal [ "abcdef" ], @stream.incoming
        end

        def test_typein_keys
          @terminal.typein Key::F1, Key::F2
          assert_equal [ "<F1>", "<F2>" ], @stream.incoming
        end

        def test_finished
          assert_equal false, @terminal.finished?
          @stream.data nil
          assert_equal true, @terminal.finished?
          assert_equal nil, @terminal.data_read_thread
          assert_raises(Session::Terminal::TerminalError) {
            @terminal.typein "\n"
          }
        end

        def test_reset
          assert_equal false, @stream.reset?
          @terminal.reset
          assert_equal true, @terminal.finished?
          assert_equal true, @stream.reset?
          assert_equal nil, @terminal.data_read_thread
          assert_equal nil, @terminal.screen_update_thread
          assert_equal nil, @terminal.screen_check_thread
          assert_raises(Session::Terminal::TerminalError) {
            @terminal.typein "\n"
          }
          assert_raises(Session::Terminal::TerminalError) {
            @terminal.start
          }
        end

        def with_data(*args)
          timeout 3 do
            @terminal.screen.lock do
              @stream.data *args
              @terminal.screen.wait_update do
                yield if block_given?
              end
            end
          end
        end

        def with_locked_screen_and_data(*args)
          sleep 0.1
          @terminal.screen.lock do
            @stream.data(*args)
            yield if block_given?
          end
        end

        def setup
          @stream = MockStream.new
          @emulator = DumbEmulator.new Screen.new
          @terminal = Terminal.new @stream, @emulator
          @terminal.start
        end

        def teardown
          @terminal.reset
          @terminal = nil
          @stream = nil
          @emulator = nil
        end
      end
    end
  end
end

