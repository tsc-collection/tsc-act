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
require 'tsc/session/screen.rb'
require 'tsc/session/key.rb'
require 'tsc/errors.rb'
require 'tsc/trace.rb'

module Session
  class Vt100Emulator < Emulator
    include TSC::Trace

    attr_accessor :tolerant

    def initialize(screen)
      super :vt100, screen

      @extended_keys = false
      @tolerant = true

      @saved_cursor = screen.cursor
      @saved_scroll_region = screen.scroll_region

      reset
    end
    
    def reset
      @mode = :text
      @params = []
      @sequence = []
      @alternate_charset = false
    end

    def key_sequence(key)
      Session::Key.convert(key).accept self
    end

    def process_data(*args)
      begin
        args.to_s.each_byte do |_byte|
          @mode = catch :switch do
            @sequence.push _byte
            send "process_#{@mode}", _byte

            @sequence.clear
            throw :switch, :text
          end
        end
      rescue Exception => exception
        reset
        raise
      end
    end

    def visit_UP(key)
      @extended_keys ? "\eOA" : "\e[A"
    end

    def visit_DOWN(key)
      @extended_keys ? "\eOB" : "\e[B"
    end

    def visit_RIGHT(key)
      @extended_keys ? "\eOC" : "\e[C"
    end

    def visit_LEFT(key)
      @extended_keys ? "\eOD" : "\e[D"
    end

    def visit_F1(key)
      "\eOP"
    end

    def visit_F2(key)
      "\eOQ"
    end

    def visit_F3(key)
      "\eOR"
    end

    def visit_F4(key)
      "\eOS"
    end

    def visit_TEXT(key)
      key.to_s
    end

    private
    #######
    def method_missing(name, *args)
      return visit_TEXT(*args) if name.to_s.index('visit_') == 0
      super name, *args
    end

    def process_text(byte)
      case byte
        when 0 then operation_ignored :zero

        when 016 
          @alternate_charset = true
        when 017 
          @alternate_charset = false

        when ?\e 
          switch_mode :control
        else
          if @alternate_charset == true
            case byte
              when ?l, ?k, ?m, ?j then byte = ?+
              when ?q then byte = ?-
              when ?x then byte = ?|
            end
          end
          screen.display byte.chr
      end
    end

    def process_control(byte)
      case byte
        when ?[ then switch_mode :control2
        when ?( then operation_ignored :select_charset_g0
        when ?) then operation_ignored :select_charset_g1
        when ?# then operation_not_implemented :line_size
        when ?D then operation_not_implemented :cursor_forward_character
        when ?E then operation_not_implemented :cursor_forward_line
        when ?H then operation_not_implemented :horisontal_tab_set
        when ?< then operation_not_implemented :cancel_vt52_emulation
        when ?1 then operation_not_implemented :graphic_processing_on
        when ?2 then operation_not_implemented :graphic_processing_off

        when ?= then operation_ignored :alternate_keypad_on
        when ?> then operation_ignored :numeric_keypad_on

        when ?7 
          @saved_cursor = screen.cursor
        when ?8 
          screen.set_cursor @saved_cursor
        when ?M # cursor up or scroll down
          cursor = screen.cursor
          scroll_region = screen.scroll_region

          if cursor.y == scroll_region.x
            screen.scroll_down 1
          else
            screen.set_cursor cursor.x, cursor.y - 1
          end
        else
          operation_failed :control2
      end
    end

    def process_control2(byte)
      case byte
        when ?h then operation_not_implemented :standard_settings
        when ?l then operation_not_implemented :standard_clearings
        when ?g then operation_not_implemented :clear_tabs
        when ?q then operation_not_implemented :programmable_leds

        when ?m then operation_ignored :set_video_attributes

        when ?A # move cursor up
          cursor = screen.cursor
          offset = @params.shift || 0

          screen.set_cursor cursor.x, (cursor.y - [ offset, 1 ].max)
        when ?B # move cursor down
          cursor = screen.cursor
          offset = @params.shift || 0

          screen.set_cursor cursor.x, cursor.y + [ offset, 1 ].max
        when ?C # move cursor forward
          cursor = screen.cursor
          offset = @params.shift || 0

          screen.set_cursor cursor.x + [ offset, 1 ].max, cursor.y
        when ?D # move cursor backward
          cursor = screen.cursor
          offset = @params.shift || 0

          screen.set_cursor cursor.x - [ offset, 1 ].max, cursor.y
        when ?H, ?f # set cursor
          cursor = screen.cursor

          y = [ @params.shift || 0, 1 ].max
          x = [ @params.shift || 0, 1 ].max

          screen.set_cursor(x - 1, y - 1)
        when ?J # erase page
          cursor = screen.cursor
          size = screen.size

          case @params.first
            when 0 
              from = (cursor.y * size.x) + cursor.x
              to = size.x * size.y
            when 1 
              from = 0
              to = (cursor.y * size.x) + cursor.x
            when 2 
              from = 0
              to = size.x * size.y
            else 
              operation_failed :erase_page
          end
          screen.erase from, to
        when ?K # erase line
          cursor = screen.cursor
          size = screen.size

          case @params.first
            when 0 
              from = (cursor.y * size.x) + cursor.x
              to = (cursor.y + 1) * size.x
            when 1 
              from = cursor.y * size.x
              to = from + cursor.x
            when 2 
              from = cursor.y * size.x
              to = from + size.x
            else
              operation_failed :erase_line
          end
          screen.erase from, to
        when ?r
          @saved_scroll_region = screen.scroll_region

          top = [ @params.shift || 0, 1 ].max
          bottom = [ @params.shift || 0, 1 ].max

          screen.set_scroll_region top - 1, bottom - 1
        when ??
          switch_mode :control3
        else
          process_parameter byte
      end
    end

    def process_control3(byte)
      case byte
        when ?h
          case @params.first
            when 1 
              @extended_keys = true
            when 7
              screen.autowrap = true
            else
              operation_failed :set
          end
        when ?l
          case @params.first
            when 1 
              @extended_keys = false
            when 7
              screen.autowrap = false
            else
              operation_failed :reset
          end
        else
          process_parameter byte
      end
    end

    def process_parameter(byte)
      case byte
        when ?;
          if @params.size < 8
            @params.push 0
            throw :switch, @mode
          end
        else
          if byte.between? ?0, ?9
            @params[-1] *= 10
            @params[-1] += (byte - ?0)

            throw :switch, @mode
          end
      end
      operation_failed @mode
    end
    
    def switch_mode(mode)
      @params = [ 0 ]
      throw :switch, mode
    end

    def sequence_string
      @sequence.map { |_byte| _byte.chr }.join
    end

    def operation_ignored(operation)
      trace "Ignoring", operation, sequence_string
    end

    def operation_not_implemented(operation)
      raise TSC::NotImplementedError.new(operation, sequence_string)
    end

    def operation_failed(operation)
      unless @tolerant
        raise TSC::OperationFailed.new(operation, sequence_string)
      end
      screen.display sequence_string
      throw :switch, @mode
    end
  end
end

if $0 == __FILE__ or defined? Test::Unit::TestCase
  require 'test/unit'
  require 'tsc/session/screen.rb'

  module Session
    class Vt100EmulatorTest < Test::Unit::TestCase
      def test_term
        assert_equal 'vt100', @emulator.term
      end

      def test_key_sequence
        assert_equal "\e[A".inspect, @emulator.key_sequence(Session::Key::UP).inspect
        assert_equal "\e[B".inspect, @emulator.key_sequence(Session::Key::DOWN).inspect
        assert_equal "\e[C".inspect, @emulator.key_sequence(Session::Key::RIGHT).inspect
        assert_equal "\e[D".inspect, @emulator.key_sequence(Session::Key::LEFT).inspect

        assert_equal "\eOP".inspect, @emulator.key_sequence(Session::Key::F1).inspect
        assert_equal "\eOQ".inspect, @emulator.key_sequence(Session::Key::F2).inspect
        assert_equal "\eOR".inspect, @emulator.key_sequence(Session::Key::F3).inspect
        assert_equal "\eOS".inspect, @emulator.key_sequence(Session::Key::F4).inspect

        assert_equal "\a".inspect, @emulator.key_sequence(Session::Key::BELL).inspect
        assert_equal "\e".inspect, @emulator.key_sequence(Session::Key::ESCAPE).inspect
        assert_equal "\f".inspect, @emulator.key_sequence(Session::Key::FORMFEED).inspect
        assert_equal "\b".inspect, @emulator.key_sequence(Session::Key::BACKSPACE).inspect
        assert_equal "\s".inspect, @emulator.key_sequence(Session::Key::SPACE).inspect
        assert_equal "\t".inspect, @emulator.key_sequence(Session::Key::TAB).inspect
        assert_equal "\n".inspect, @emulator.key_sequence(Session::Key::ENTER).inspect
        assert_equal "\r".inspect, @emulator.key_sequence(Session::Key::RETURN).inspect

        assert_equal "<F5>".inspect, @emulator.key_sequence(Session::Key::F5).inspect
        assert_equal "<F6>".inspect, @emulator.key_sequence(Session::Key::F6).inspect

        assert_equal 'hello', @emulator.key_sequence(:hello)
      end

      def test_key_sequence_switch
        assert_equal "\e[A".inspect, @emulator.key_sequence(Session::Key::UP).inspect
        assert_equal "\e[B".inspect, @emulator.key_sequence(Session::Key::DOWN).inspect
        assert_equal "\e[C".inspect, @emulator.key_sequence(Session::Key::RIGHT).inspect
        assert_equal "\e[D".inspect, @emulator.key_sequence(Session::Key::LEFT).inspect

        @emulator.process_data "\e[?1h"

        assert_equal "\eOA".inspect, @emulator.key_sequence(Session::Key::UP).inspect
        assert_equal "\eOB".inspect, @emulator.key_sequence(Session::Key::DOWN).inspect
        assert_equal "\eOC".inspect, @emulator.key_sequence(Session::Key::RIGHT).inspect
        assert_equal "\eOD".inspect, @emulator.key_sequence(Session::Key::LEFT).inspect

        @emulator.process_data "\e[?1l"

        assert_equal "\e[A".inspect, @emulator.key_sequence(Session::Key::UP).inspect
        assert_equal "\e[B".inspect, @emulator.key_sequence(Session::Key::DOWN).inspect
        assert_equal "\e[C".inspect, @emulator.key_sequence(Session::Key::RIGHT).inspect
        assert_equal "\e[D".inspect, @emulator.key_sequence(Session::Key::LEFT).inspect
      end

      def test_process_text
        @emulator.process_data "hello", :World
        assert_equal 'helloWorld', @screen.lines[0].strip
      end

      def test_set_charsets
        assert_raises TSC::NotImplementedError do
          @emulator.process_data "\016"
        end
        assert_raises TSC::NotImplementedError do
          @emulator.process_data "\017"
        end
      end

      def test_save_restore_cursor
        @emulator.process_data "abcd"
        cursor = @screen.cursor

        @emulator.process_data "\e7"
        assert_equal cursor, @screen.cursor

        @emulator.process_data "zzzz"
        assert_not_equal cursor, @screen.cursor

        @emulator.process_data "\e8"
        assert_equal cursor, @screen.cursor
      end

      def test_wrong_control
        @emulator.process_data "\eZ"
        assert_equal "\eZ".inspect, @screen.lines[0].strip.inspect
      end

      def test_wrong_control2
        @emulator.process_data "\e[3Z"
        assert_equal "\e[3Z".inspect, @screen.lines[0].strip.inspect
      end

      def test_wrong_control3
        @emulator.process_data "\e[?12;14Z"
        assert_equal "\e[?12;14Z".inspect, @screen.lines[0].strip.inspect
      end

      def test_move_cursor
        @emulator.process_data "\e[10;5H"
        assert_equal Pair[4,9], @screen.cursor

        @emulator.process_data "\e[A"
        assert_equal Pair[4,8], @screen.cursor

        @emulator.process_data "\e[2B"
        assert_equal Pair[4,10], @screen.cursor

        @emulator.process_data "\e[D"
        assert_equal Pair[3,10], @screen.cursor

        @emulator.process_data "\e[12C"
        assert_equal Pair[15,10], @screen.cursor

        @emulator.process_data "\e[1;1f"
        assert_equal Pair[0,0], @screen.cursor

        @emulator.process_data "\e[4;8H"
        assert_equal Pair[7,3], @screen.cursor

        @emulator.process_data "\e[H"
        assert_equal Pair[0,0], @screen.cursor

        @emulator.process_data "\e[12;15H"
        assert_equal Pair[14,11], @screen.cursor

        @emulator.process_data "\e[19H"
        assert_equal Pair[0,18], @screen.cursor
      end

      def test_cursor_up_with_scroll
        @screen.display "aaa\nbbb\nccc\nddd\n"
        @screen.set_scroll_region 1, 2
        @screen.set_cursor 1, 2

        @emulator.process_data "\eM"
        assert_equal Pair[1,1], @screen.cursor
        assert_equal [ 
          "aaa", "bbb", "ccc", "ddd", *Array.new(20, "")
        ], @screen.lines.map {|_line| _line.gsub(%r{\s+$},'') }

        @emulator.process_data "\eM"
        assert_equal Pair[1,1], @screen.cursor
        assert_equal [ 
          "aaa", "", "bbb", "ddd", *Array.new(20, "")
        ], @screen.lines.map {|_line| _line.gsub(%r{\s+$},'') }
      end

      def test_erase_page
        @screen.display "aaa\nbbb\nccc\nddd\neee"
        @screen.set_cursor 1, 3
        assert_equal [ 
          "aaa", "bbb", "ccc", "ddd", "eee", *Array.new(19, "")
        ], @screen.lines.map {|_line| _line.gsub(%r{\s+$},'') }

        @emulator.process_data "\e[J"
        assert_equal [ 
          "aaa", "bbb", "ccc", "d", "", *Array.new(19, "")
        ], @screen.lines.map {|_line| _line.gsub(%r{\s+$},'') }

        @screen.set_cursor 2, 1
        @emulator.process_data "\e[1J"
        assert_equal [ 
          "", "  b", "ccc", "d", "", *Array.new(19, "")
        ], @screen.lines.map {|_line| _line.gsub(%r{\s+$},'') }

        @screen.set_cursor 2, 2
        @emulator.process_data "\e[2J"
        assert_equal [ 
          "", "", "", "", "", *Array.new(19, "")
        ], @screen.lines.map {|_line| _line.gsub(%r{\s+$},'') }
      end

      def test_erase_line
        @screen.display "abcdefg"
        assert_match %r{^abcdefg\s+$}, @screen.lines[0]

        @screen.set_cursor 3, 0
        @emulator.process_data "\e[K"
        assert_match %r{^abc\s+$}, @screen.lines[0]

        @screen.set_cursor 0, 1
        @screen.display "abcdefg"
        assert_match %r{^abcdefg\s+$}, @screen.lines[1]
        @screen.set_cursor 3, 1
        @emulator.process_data "\e[1K"
        assert_match %r{^   defg\s+$}, @screen.lines[1]

        @screen.set_cursor 0, 2
        @screen.display "abcdefg"
        assert_match %r{^abcdefg\s+$}, @screen.lines[2]
        @screen.set_cursor 3, 2
        @emulator.process_data "\e[2K"
        assert_match %r{^\s+$}, @screen.lines[2]
      end

      def test_set_scroll_region
        @emulator.process_data "\e[3;5r"
        assert_equal Pair[2,4], @screen.scroll_region
      end

      def setup
        @screen = Screen.new
        @emulator = Vt100Emulator.new @screen
        @screen.newline_assumes_return = true
      end

      def teardown
        @emulator = nil
        @screen = nil
      end
    end
  end
end
