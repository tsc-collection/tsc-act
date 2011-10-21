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

require 'tsc/synchro-queue.rb'
require 'tsc/errors.rb'
require 'tsc/monitor.rb'

module TSC
  module Session
    class S3270Stream 
      def initialize(host)
        @host = host
        @queue = SynchroQueue.new true
        @data = SynchroQueue.new false
        @monitor = TSC::Monitor.new
        @error_handler_thread = Thread.current

        start
      end

      def get_available_data
        @data.get
      end

      def reset
        stop
      end

      def write(commands)
        @monitor.synchronize do
          stop_checker_thread
          begin
            @data.put commands.map.push('ascii').map { |_line|
              run :write, _line
            }.last
          ensure
            start_checker_thread
          end
        end
      end

      private
      #######
      def start
        stop

        sigint_handler = trap "SIGINT", "IGNORE"
        sigquit_handler = trap "SIGQUIT", "IGNORE"

        @s3270 = IO::popen('s3270', 'w+')

        trap "SIGINT", (sigint_handler or "DEFAULT")
        trap "SIGQUIT", (sigquit_handler or "DEFAULT")

        start_reader_thread
        write "connect #{@host.inspect}"
      end

      def stop
        if @s3270
          stop_reader_thread
          stop_checker_thread

          @s3270.close
          @s3270 = nil
        end
      end

      def start_reader_thread
        @reader = Thread.new do
          TSC::Error.relay @error_handler_thread do
            loop do 
               responce = []
               @s3270.each do |_line|
                 content = _line.chomp
                 responce.push content
                 break if [ "ok", "error" ].include? content
               end
               @queue.put responce
            end
          end
        end
      end

      def stop_reader_thread
        if @reader 
          @reader.exit
          @reader = nil
        end
      end

      def start_checker_thread
        @checker = Thread.new do
          Thread.pass
          TSC::Error.relay @error_handler_thread do
            loop do
              @monitor.synchronize do
                @s3270.puts "wait(1,output)"
                responce = @queue.get(5)
                if responce.last == 'ok'
                  @data.put run(:check, "ascii")
                end
              end
            end
          end
        end
      end

      def stop_checker_thread
        if @checker
          @checker.exit
          @checker = nil
        end
      end

      def run(name, command)
        @s3270.puts command
        responce = @queue.get(30)
        unless responce.last == "ok"
          raise TSC::OperationFailed.new(name, responce)
        end
        unless responce.slice(-2).split.slice(3) == "C(#{@host})"
          raise TSC::OperationCanceled.new(:connect, responce)
        end
        responce
      end
    end
  end
end

if $0 == __FILE__ or defined? Test::Unit::TestCase
  require 'test/unit'
  require 'tsc/session/screen.rb'

  module TSC
    module Session
      class S3270StreamTest < Test::Unit::TestCase
        def test_create
          assert_equal 'ok', @stream.get_available_data.last
        end
        def setup
          @stream = S3270Stream.new 'localhost'
        end
        def teardown
          @stream = nil
        end
      end
    end
  end
end
