#
#            Tone Software Corporation BSD License ("License")
# 
#                       Acceptance Testing Framework
# 
# Please read this License carefully before downloading this software. By
# downloading or using this software, you are agreeing to be bound by the
# terms of this License. If you do not or cannot agree to the terms of
# this License, please do not download or use the software.
# 
# Provides facility for creating custom test suites for
# acceptance/regression testing. The engine allows interfacing a system to
# be tested through a variety of means such as a process on a local host
# via a PTY (pseudo terminal), a network host via TELNET, an MVS host via
# 3270 protocol, etc. An internal screen image for the system under test
# is constantly maintained, with ability to examine it and to handle
# various events. Input to the system under test can be generated with
# support for functional keys. Ruby test/unit framework is readily
# available for assertions.
#      
# Copyright (c) 2003, 2004, Tone Software Corporation
#      
# All rights reserved.
#      
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are
# met:
#   * Redistributions of source code must retain the above copyright
#     notice, this list of conditions and the following disclaimer. 
#   * Redistributions in binary form must reproduce the above copyright
#     notice, this list of conditions and the following disclaimer in the
#     documentation and/or other materials provided with the distribution. 
#   * Neither the name of the Tone Software Corporation nor the names of
#     its contributors may be used to endorse or promote products derived
#     from this software without specific prior written permission. 
# 
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS
# IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
# TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
# PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER
# OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
# EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
# PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
# PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
# LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
# NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
# 


module Session
  class Key
    attr_reader :name, :value

    def initialize(name,value,visitor_method)
      @name = name
      @value = value || "<#{name}>"
      @visitor_method = visitor_method
    end
    def accept(visitor,*args)
      visitor.send @visitor_method, self, *args
    end
    def to_s
      @value
    end
    def to_key
      self
    end
    def self.convert(arg)
      arg.respond_to?(:to_key) ? arg.to_key : self.text(arg)
    end
    def self.text(string)
      new('TEXT',string.to_s,'visit_TEXT'.intern)
    end
    def self.define_key(*args)
      args.each do |key|
	key.to_a.each do |key|
	  name, value = key.to_a
	  const_set name, new("#{name}",value,"visit_#{name}".intern)
	end
      end
    end

    define_key :BELL => "\a"
    define_key :ESCAPE => "\e"
    define_key :FORMFEED => "\f"
    define_key :BACKSPACE => "\b"
    define_key :SPACE => "\s"
    define_key :TAB => "\t"
    define_key :ENTER => "\n"
    define_key :RETURN => "\r"
    define_key :NEWLINE => "\n"

    define_key :UP, :DOWN, :LEFT, :RIGHT, :PAGEUP, :PAGEDOWN
    define_key :KP_HOME, :KP_END, :INSERT, :DELETE, :BACKTAB
    define_key :F1, :F2, :F3, :F4, :F5, :F6, :F7, :F8, :F9, :F10, :F11, :F12

    define_key :BREAK, :DROPLINE, :SCREEN

    private_class_method :new
    freeze
  end
end

if $0 != '-e' and $0 == __FILE__ or defined? Test::Unit::TestCase
  require 'test/unit'

  module Session
    class KeyTest < Test::Unit::TestCase
      def test_key_names
	assert_equal Key::BELL.name, 'BELL'
	assert_equal Key::ESCAPE.name, 'ESCAPE'
	assert_equal Key::FORMFEED.name, 'FORMFEED'
	assert_equal Key::BACKSPACE.name, 'BACKSPACE'
	assert_equal Key::SPACE.name, 'SPACE'
	assert_equal Key::TAB.name, 'TAB'
	assert_equal Key::BACKTAB.name, 'BACKTAB'
	assert_equal Key::ENTER.name, 'ENTER'
	assert_equal Key::RETURN.name, 'RETURN'
	assert_equal Key::NEWLINE.name, 'NEWLINE'
	assert_equal Key::UP.name, 'UP'
	assert_equal Key::DOWN.name, 'DOWN'
	assert_equal Key::LEFT.name, 'LEFT'
	assert_equal Key::RIGHT.name, 'RIGHT'
	assert_equal Key::PAGEUP.name, 'PAGEUP'
	assert_equal Key::PAGEDOWN.name, 'PAGEDOWN'
	assert_equal Key::KP_HOME.name, 'KP_HOME'
	assert_equal Key::KP_END.name, 'KP_END'
	assert_equal Key::INSERT.name, 'INSERT'
	assert_equal Key::DELETE.name, 'DELETE'
	assert_equal Key::F1.name, 'F1'
	assert_equal Key::F2.name, 'F2'
	assert_equal Key::F3.name, 'F3'
	assert_equal Key::F4.name, 'F4'
	assert_equal Key::F5.name, 'F5'
	assert_equal Key::F6.name, 'F6'
	assert_equal Key::F7.name, 'F7'
	assert_equal Key::F8.name, 'F8'
	assert_equal Key::F9.name, 'F9'
	assert_equal Key::F10.name, 'F10'
	assert_equal Key::F11.name, 'F11'
	assert_equal Key::F12.name, 'F12'
	assert_equal Key::BREAK.name, 'BREAK'
	assert_equal Key::DROPLINE.name, 'DROPLINE'
      end 
      def test_accept
	keys = [ Key::F1, Key::BREAK ]
	
	assert !@depot['F1']
	assert !@depot['BREAK']

	keys.each do |key|
	  key.accept(self)
	end

	assert @depot['F1']
	assert @depot['BREAK']
      end
      def test_text
	key = Key.text("abcdef")
	assert_equal 'TEXT', key.name
	assert_equal 'abcdef',key.value
	assert !@depot['TEXT']
	key.accept(self)
	assert_equal 'abcdef', @depot['TEXT']
      end
      def test_convert
	assert_equal Key::F1, Key.convert(Key::F1)
	assert_equal Key::ENTER, Key.convert(Key::ENTER)
	assert_equal 'TEXT', Key.convert('abcdef').name
	assert_equal 'abcdef', Key.convert('abcdef').value
      end

      def setup
	@depot = Hash.new
      end
      def teardown
	@depot = nil
      end

      private
      #######
      def visit_F1(key)
	@depot['F1'] = true
      end
      def visit_BREAK(key)
	@depot['BREAK'] = true
      end
      def visit_TEXT(key)
	@depot['TEXT'] = key.value
      end
    end
  end
end
