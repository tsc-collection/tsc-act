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

require 'tsc/session/emulator.rb'
require 'tsc/session/key.rb'
require 'tsc/session/screen.rb'
require 'tsc/string.rb'

module Session
  class S3270Emulator < Session::Emulator
    def initialize(screen)
      super :ibm3270, screen
    end

    def key_sequence(key)
      Session::Key.convert(key).accept self
    end

    def process_data(*args)
      args.each do |_responce|
        if _responce.slice(-1) == 'ok'
          hight, width, y, x = _responce.slice(-2).split.slice(6,4)

          content = _responce.map { |_line|
            [ *%r{^(data: )(.*)$}.match(_line) ].slice(2)
          }
          screen.lock do
            screen.resize_and_clear width, hight
            screen.display content.join
            screen.set_cursor x, y
          end
        end
      end
    end

    def visit_UP(key)
      'up'
    end

    def visit_DOWN(key)
      'down'
    end

    def visit_RIGHT(key)
      'right'
    end

    def visit_LEFT(key)
      'left'
    end

    def visit_PAGEDOWN(key)
      'pf 7'
    end

    def visit_PAGEUP(key)
      'pf 8'
    end

    def visit_KP_HOME(key)
      'home'
    end

    def visit_KP_END(key)
      'fieldend'
    end

    def visit_TAB(key)
      'tab'
    end

    def visit_DELETE(key)
      'delete'
    end

    def visit_BACKTAB(key)
      'backtab'
    end

    def visit_INSERT(key)
      'toggleinsert'
    end

    def visit_SPACE(key)
      'string " "'
    end

    def visit_BACKSPACE(key)
      'backspace'
    end

    def visit_NEWLINE(key)
      'newline'
    end

    def visit_RETURN(key)
      'enter'
    end

    def visit_ENTER(key)
      'enter'
    end

    def visit_F1(key)
      'pf 1'
    end

    def visit_F2(key)
      'pf 2'
    end

    def visit_F3(key)
      'pf 3'
    end

    def visit_F4(key)
      'pf 4'
    end

    def visit_F5(key)
      'pf 5'
    end

    def visit_F6(key)
      'pf 6'
    end

    def visit_F7(key)
      'pf 7'
    end

    def visit_F8(key)
      'pf 8'
    end

    def visit_F9(key)
      'pf 9'
    end

    def visit_F10(key)
      'pf 10'
    end

    def visit_F11(key)
      'pf 11'
    end

    def visit_F12(key)
      'pf 12'
    end

    def visit_SCREEN(key)
      'ascii'
    end

    def visit_BREAK(key)
      'reset'
    end

    def visit_FORMFEED(key)
      'pf 7'
    end

    def visit_BELL(key)
      ''
    end

    def visit_ESCAPE(key)
      'interrupt'
    end

    def visit_TEXT(key)
      TSC::String.new(key.to_s).split_keep_separator(%r([\b\n\r\t])).map { |_line|
        case _line
          when "\b" then "backspace"
          when "\n" then "enter"
          when "\r" then "enter"
          when "\t" then "tab"
          else
            "string #{_line.inspect}" unless _line.empty?
        end
      }.compact.join("\n")
    end

    private
    #######
    def method_missing(name, *args)
      return visit_TEXT(*args) if name.to_s.index('visit_') == 0
      super name, *args
    end
  end
end

if $0 == __FILE__ or defined? Test::Unit::TestCase
  require 'test/unit'
  require 'session/mvs-screen.rb'

  module Session
    class S3270EmulatorTest < Test::Unit::TestCase
      def test_term
        assert_equal 'ibm3270', @emulator.term
      end

      def test_key_sequence
        assert_equal '"up"', @emulator.key_sequence(Session::Key::UP).inspect
        assert_equal '"down"', @emulator.key_sequence(Session::Key::DOWN).inspect
        assert_equal '"right"', @emulator.key_sequence(Session::Key::RIGHT).inspect
        assert_equal '"left"', @emulator.key_sequence(Session::Key::LEFT).inspect

        assert_equal '"pf 1"', @emulator.key_sequence(Session::Key::F1).inspect
        assert_equal '"pf 2"', @emulator.key_sequence(Session::Key::F2).inspect
        assert_equal '"pf 3"', @emulator.key_sequence(Session::Key::F3).inspect
        assert_equal '"pf 4"', @emulator.key_sequence(Session::Key::F4).inspect
        assert_equal '"pf 5"', @emulator.key_sequence(Session::Key::F5).inspect
        assert_equal '"pf 6"', @emulator.key_sequence(Session::Key::F6).inspect

        assert_equal '"string \" \""', @emulator.key_sequence(Session::Key::SPACE).inspect
        assert_equal '"backspace"', @emulator.key_sequence(Session::Key::BACKSPACE).inspect
        assert_equal '"tab"', @emulator.key_sequence(Session::Key::TAB).inspect
        assert_equal '"backtab"', @emulator.key_sequence(Session::Key::BACKTAB).inspect
        assert_equal '"enter"', @emulator.key_sequence(Session::Key::ENTER).inspect
        assert_equal '"enter"', @emulator.key_sequence(Session::Key::RETURN).inspect
        assert_equal '"newline"', @emulator.key_sequence(Session::Key::NEWLINE).inspect

        assert_equal '"pf 7"', @emulator.key_sequence(Session::Key::FORMFEED).inspect
        assert_equal '""', @emulator.key_sequence(Session::Key::BELL).inspect
        assert_equal '"interrupt"', @emulator.key_sequence(Session::Key::ESCAPE).inspect

        assert_equal '"string \"hello\""', @emulator.key_sequence(:hello).inspect
        assert_equal '"string \"hello\"\nenter\nstring \"World\""', @emulator.key_sequence("hello\nWorld").inspect
        assert_equal '"enter"', @emulator.key_sequence("\n").inspect
        assert_equal '""', @emulator.key_sequence('').inspect
      end

      def test_special_symbols
        assert_equal '"backspace\nbackspace\nenter\nenter\ntab\nenter"', @emulator.key_sequence("\b\b\n\r\t\n").inspect
        assert_equal '"string \"ab\"\nbackspace\nbackspace\nstring \"cd\""', @emulator.key_sequence("ab\b\bcd").inspect
        assert_equal '"tab\nstring \"abc\""', @emulator.key_sequence("\tabc").inspect
      end

      def setup
        @screen = MvsScreen.new
        @emulator = S3270Emulator.new @screen
      end

      def teardown
        @emulator = nil
        @screen = nil
      end
    end
  end
end
