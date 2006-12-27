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

require 'tsc/session/terminal.rb'
require 'tsc/errors.rb'

module TSC
  module Session
    class Manager
      attr_reader :prompt
      attr_writer :verbose

      def initialize(stream, prompt = nil)
        @error_handler_thread = Thread.current
        @prompt = Regexp.new(prompt || "[$%#>]\s+$")
        @stream = stream
      end

      def terminal
        @terminal ||= begin
          Terminal.new @stream, emulator
        end
      end

      def verbose?
        @verbose ? true : false
      end
      
      protected
      #########

      def activate(&block)
        raise "No block given" unless block

        Thread.new do
          TSC::Error.relay @error_handler_thread do
            begin 
              terminal.start
              if verbose?
                terminal.screen.show
                terminal.start_screen_check
              end
              block.call terminal
            ensure
              terminal.reset
            end
          end
        end
      end

      def login(user, password)
        terminal.screen.lock do
          terminal.screen.wait_prompt %r{ogin:\s*}, 2
          terminal.typein "#{user}\n"

          terminal.screen.wait_prompt %r{assword:\s*}, 2
          terminal.typein "#{password}\n"

          terminal.screen.wait_prompt prompt, 2
        end
      end

      def fix_terminal_size
        terminal.screen.lock do
          terminal.screen.wait_prompt prompt, 2
          terminal.typein "stty rows #{terminal.screen.size.y} cols #{terminal.screen.size.x}\n"

          terminal.screen.wait_prompt prompt, 2
          terminal.typein "LINES=#{terminal.screen.size.y} export LINES\n"

          terminal.screen.wait_prompt prompt, 2
          terminal.typein "COLUMNS=#{terminal.screen.size.x} export COLUMNS\n"

          terminal.screen.wait_prompt prompt, 2
          terminal.typein "COLS=#{terminal.screen.size.x} export COLS\n"

          terminal.screen.wait_prompt prompt, 2
        end
      end

      def fix_terminal_type
        terminal.screen.lock do
          terminal.screen.wait_prompt prompt, 2
          terminal.typein "TERM='#{terminal.term}' export TERM\n"

          terminal.screen.wait_prompt prompt, 2
        end
      end

      def emulator
        raise TSC::NotImplementedError, :emulator
      end
    end
  end
end

