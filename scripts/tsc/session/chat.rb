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

require 'tsc/trace'
require 'tsc/array'

module TSC
  module Session
    class Chat
      include TSC::Trace

      attr_writer :time_to_complete, :prompt_delay, :eol

      def initialize(communicator,prompts,time_to_complete = 10,prompt_delay = 1)
        @eol = "\r"
        @communicator = communicator
        @prompts = prompts
        @screen = communicator.screen
        @time_to_complete = time_to_complete
        @prompt_delay = prompt_delay
      end

      def start(*responses,&action)
        @screen.lock do
          @prompts.collect_with(responses).each do |entry|
            trace "Waiting for #{entry[0].inspect}..."
            @screen.wait_prompt(*parse_prompt(*entry[0])) do 
              trace "Sending #{entry[1].inspect}..."
              @communicator.typein "#{entry[1]}#{@eol}" unless entry[1].nil?
            end
          end
          action.call unless action.nil?
        end
        self
      end

      private
      #######
      def parse_prompt(*args)
        [ args[0], args[1] || @time_to_complete, args[2] || @prompt_delay ]
      end
    end
  end
end

if $0 != '-e' and $0 == __FILE__ or defined? Test::Unit::TestCase
  require 'test/unit'
  require 'tsc/session/screen.rb'

  module TSC
    module Session
      class ChatTest < Test::Unit::TestCase
        class MockScreen < Session::Screen
          attr_reader :prompts
          def initialize
            super
            @prompts = []
          end

          def wait_prompt(prompt,time_to_complete,time_no_update)
            super prompt, time_to_complete, time_no_update
            @prompts.push [ prompt, time_to_complete, time_no_update ]
          end
        end

        class MockCommunicator
          attr_reader :screen
          attr_accessor :eol

          def initialize
            @screen = MockScreen.new
          end

          def typein(*args)
            case args.to_s
              when 'Login: ' then @screen.display "\r\n\nLogin: "
              when "login#{@eol}" then @screen.display "login\r\nPassword: "
              when "password#{@eol}" then @screen.display "\r\n\n\n$ "
            end
          end

          def show_screen
            @screen.show do |line|
              $stderr.puts line
            end
          end
        end

        def test_login_and_eol
          @chat.eol = "\r\n"
          @communicator.eol = "\r\n"

          @chat.start('login', 'password')
          assert_equal [
            ['Login: ', 7, 1],
            ['Password: ', 4, 2],
            ['$ ', 2, 1]
          ], @communicator.screen.prompts
        end

        def test_different_timeouts
          @communicator.typein 'Login: '
          @chat.time_to_complete = 4
          @chat.prompt_delay = 0
          @chat.start('login', 'password')
          assert_equal [
            ['Login: ', 4, 0],
            ['Password: ', 4, 2],
            ['$ ', 2, 0]
          ], @communicator.screen.prompts
        end

        def setup
          @communicator = MockCommunicator.new
          @communicator.eol = "\r"
          @chat = Session::Chat.new @communicator, [ 
            'Login: ', 
            [ 'Password: ', 4, 2], 
            ['$ ',2]
          ], 7, 1
          @communicator.typein 'Login: '
        end

        def teardown
          @chat = nil
          @communicator = nil
          GC.start
        end
      end
    end
  end
end
  
