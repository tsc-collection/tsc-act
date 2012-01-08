=begin
  vim: sw=2:

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

require 'net/telnet'
require 'timeout'
require 'tsc/session/controller.rb'
require 'sk/net/endpoint.rb'

module TSC
  module Session
    module Telnet
      class Stream < Net::Telnet
        class << self
          def activate(host, arranger = nil, &block)
            TSC::Session::Controller.new(stream(host), emulator, arranger).activate(&block)
          end

          def stream(host)
            self.new host
          end

          def emulator
            TSC::Session::Emulator::Vt100.new TSC::Session::Screen.new, true
          end
        end

        attr_reader :endpoint

        def initialize(host, port = nil)
          @endpoint = SK::Net::Endpoint.new(host, port, 23)
          super 'Host' => @endpoint.host, 'Port' => @endpoint.port
        end

        def get_available_data
          begin
            waitfor /./
          rescue TimeoutError
            retry
          rescue
            nil
          end or raise EOFError, "Connection to #{endpoint.inspect} closed on remote request"
        end

        def reset
          self.close_read
          self.close_write
        end
      end
    end
  end
end
