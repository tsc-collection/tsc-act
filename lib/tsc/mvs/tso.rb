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

require 'tsc/session/key.rb'
require 'tsc/session/screen.rb'
require 'tsc/mvs/pts-info.rb'

module TSC
  module Mvs
    class Tso
      def initialize(terminal, screen_timeout = 10)
        @terminal = terminal
        @screen = terminal.screen
        @screen_timeout = screen_timeout
      end

      def logon(user, passwd, &block)
        screen.lock do
          logoff &block

          loop do
            ensure_start_page
            terminal.typein 'tso ', user, Key::ENTER

            action = catch :action do
              loop do
                screen.wait_condition(screen_timeout) {
                  ensure_not_start_page
                  throw :action, :ready if ready_prompt?

                  block.call if block
                  condition = true
                  case 
                    when attempt_to_reconnect? 
                      terminal.typein Key::ENTER
                    when reconnect_successful? 
                      terminal.typein Key::ENTER
                      throw :action, :logoff
                    when logon_error_line.empty? == false
                      raise logon_error_line
                    when password_request? 
                      terminal.typein passwd, Key::ENTER
                    else 
                      condition = false
                  end
                  condition
                }
              end
            end
            case action
              when :logoff then logoff &block
              when :ready then break
              else
                raise "Unknown action #{action.inspect}"
            end
          end
        end
      end

      def logoff(&block)
        screen.lock do
          return if start_page?
          if logon_page?
            terminal.typein Key::F3
            return
          end

          to_ready_prompt &block
          terminal.typein 'logoff', Key::ENTER
          screen.wait_condition(screen_timeout) {
            block.call if block
            start_page?
          }
        end
      end

      def to_ready_prompt(&block)
        screen.lock do
          return if ready_prompt?
          terminal.typein Key::F3
          catch :done do
            loop do
              screen.wait_condition(screen_timeout) {
                ensure_not_start_page
                block.call if block

                throw :done if ready_prompt?
                condition = true
                case
                  when command_prompt? then terminal.typein Key::F3
                  when log_disposition_request? then terminal.typein '2', Key::ENTER
                  when wish_request? then terminal.typein 'yes', Key::ENTER
                  else
                    condition = false
                end
                condition
              }
            end
          end
        end
      end

      def ispf(&block)
        screen.lock do
          to_ready_prompt &block

          terminal.typein 'ispf', Key::ENTER
          screen.wait_condition(screen_timeout) {
            ensure_not_start_page
            block.call if block

            command_prompt? if screen.line(2).strip == 'ISPF Primary Option Menu'
          }
        end
      end

      def tsc10(&block)
        screen.lock do
          ispf &block

          terminal.typein 'tsc.10', Key::ENTER
          pattern = %r{^\s*[-]+\s+Problem Tracking System\s+[-]+\s*$}
          screen.wait_condition(screen_timeout) {
            ensure_not_start_page
            block.call if block

            command_prompt? if screen.line(0) =~ pattern
          }
        end
      end

      def tsc15(&block)
        screen.lock do
          ispf &block

          terminal.typein 'tsc.15', Key::ENTER
          pattern = %r{^\s*[-]+\s+TSC Marketing System\s+[-]+\s*$}
          screen.wait_condition(screen_timeout) {
            ensure_not_start_page
            block.call if block

            command_prompt? if screen.line(0) =~ pattern
          }
        end
      end

      def refresh_item(item, &block)
        screen.lock do
          tsc10 &block

          if item.pts?
            terminal.typein Array.new(2, Key::TAB)
          elsif item.prj?
            terminal.typein Array.new(3, Key::TAB)
          else
            raise "Unknown type for item #{item.inspect}"
          end
          terminal.typein item.number, Key::ENTER

          body = []
          label = nil
          top_of_data = %r{^\s*[*]+\s+[*]+\s+Top\s+of\s+Data\s+[*]+\s*$}
          bottom_of_data = %r{^\s*[*]+\s+[*]+\s+Bottom\s+of\s+Data\s+[*]+\s*$}

          catch :done do
            loop do
              screen.wait_condition(screen_timeout) {
                ensure_not_start_page
                block.call if block

                label ||= (0 if screen.line_from_cursor(1) =~ top_of_data)

                if label
                  start_found = false
                  screen.lines.each { |_line|
                    throw :done, body if _line =~ bottom_of_data

                    result = [ *%r{^ (\d{6,6}) (.*)$}.match(_line) ]
                    unless start_found
                      next if result.empty?
                      break unless result.slice(1).to_i > label
                      start_found = true
                    end
                    unless result.empty?
                      body.push result.slice(2)
                      label = result.slice(1).to_i
                    end
                  }
                  if start_found
                    terminal.typein Key::F8
                    true
                  end
                end
              }
            end
          end
        end
      end

      def tasks(&block)
        screen.lock do
          ispf &block

          terminal.typein 'tso ts', Key::ENTER
          pattern = %r{^\s*[-]+\s+Time Sheet Update\s+[-]+\s+Row (\d+) to (\d+) of (\d+)\s*$}
          catch :result do
            screen.wait_condition(screen_timeout) {
              ensure_not_start_page
              block.call if block

              if command_prompt? 
                result = [ *pattern.match(screen.line(0)) ]
                unless result.empty?
                  amount = result.slice(2).to_i - result.slice(1).to_i + 1
                  throw :result, [ *screen.lines.slice(8, amount) ].map { |_line|
                    name = _line.slice(3,8).strip
                    description = _line.slice(17,35).strip
                    PtsInfo.new name, nil, nil, nil, nil, nil, description
                  }
                end
              end
            }
          end
        end
      end

      def reviews(&block)
        screen.lock do
          tsc10 &block

          terminal.typein Key::ENTER
          pattern = %r{^\s*[-]+\s+Problem Tracking System\s+(Index)?\s+[-]+\s*(\S+)\s+matches\s*$}
          catch :result do
            screen.wait_condition(screen_timeout) {
              ensure_not_start_page
              block.call if block

              if command_prompt? 
                result = pattern.match screen.line(0)
                if result 
                  amount = result.to_a.slice(2).to_i
                  throw :result, [ *screen.lines.slice(5, [ screen.size.y - 8, amount ].min) ].map { |_line|
                    PtsInfo.new *_line.scan(%r{^\s*#{'(\S+)\s*' * 6}(.*)$}).first
                  }
                end
              end
            }
          end
        end
      end

      private
      #######
      attr_reader :terminal, :screen, :screen_timeout

      def start_page?
        screen.line(2).strip == 'W E L C O M E T O  T H E'
      end

      def ensure_not_start_page
        raise 'Unexpected start page' if start_page?
      end

      def ensure_start_page
        raise 'No start page' unless start_page?
      end

      def ready_prompt?
        screen.line_from_cursor(-1).strip == 'READY'
      end

      def command_prompt?
        screen.line_upto_cursor(0) =~ %r{\s+===>\s+$}
      end

      def log_disposition_request?
        if screen.line(0).strip == 'Specify Disposition of Log Data Set'
          screen.line_upto_cursor(0) =~ %r{Process Option . . . . $}
        end
      end

      def wish_request?
        screen.line_upto_cursor(0) =~ %r{Do you wish .*[?]\s+$}
      end

      def password_request?
        if logon_page?
          screen.line_upto_cursor(0) =~ %r{^\s*Password\s+===>\s+$}
        end
      end

      def logon_page?
        screen.line(0) =~ %r{^\s*[-]+\s+TSO/E\s+LOGON\s+[-]+\s*$}
      end

      def attempt_to_reconnect?
        screen.line(0).strip == 'Attempting to reconnect. Press enter to continue...'
      end

      def reconnect_successful?
        screen.line(0) =~ %r{LOGON RECONNECT SUCCESSFUL, SESSION ESTABLISHED}
      end

      def logon_error_line
        screen.line(1).strip
      end
    end
  end
end
