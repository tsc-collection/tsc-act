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

require 'tsc/monitor'

require 'tsc/trace'
require 'tsc/session/pair'
require 'tsc/session/line-buffer'

module TSC
  module Session
    class Screen 
      TABSTOP = 8
      include TSC::Trace

      attr_reader :mutex, :update_condition, :update_counter
      attr_writer :newline_assumes_return, :autowrap

      attr_accessor :title

      def debug
        false
      end

      public
      ######
      def lines
        @area.collect { |_line| _line.clone }
      end

      def line(index)
        "#{@area.slice(index)}"
      end

      def line_from_cursor(offset)
        index = cursor.y + offset
        return '' unless index.between? 0, size.y - 1

        "#{@area.slice(index)}"
      end
      
      def line_upto_cursor(offset)
        x = [ [ 0, cursor.x + offset ].max, size.x ].min
        "#{@area.slice(cursor.y).slice(0, x)}"
      end

      def lines_upto_cursor_since(*args, &block)
        block ||= proc do |_line|
          args.detect { |_pattern|
            _line =~ _pattern
          }
        end

        array = []
        @area[0, cursor.y].reverse_each do |_line|
          line = _line.clone
          break if block.call line
          array.unshift line
        end
        array
      end

      def size
        @size.clone
      end

      def cursor
        @cursor.clone
      end
      
      def cursor_at?(*args)
        @cursor == Pair.new(*args)
      end

      def scroll_region
        @scroll_region.clone
      end

      def updated?
        return @update_counter > 0
      end

      def lock(&action)
        trace
        unless action.nil?
          @mutex.synchronize do
            action.call self
          end
        end
      end

      def reset_update
        @update_counter = 0
      end

      def wait_update(time_to_wait = nil, &action)
        trace
        is_update = true
        self.lock do
          if @update_counter == 0 
            is_update = @update_condition.wait time_to_wait
          end
          @update_counter = 0
          action.call self unless action.nil?
        end
        is_update
      end

      def wait_no_update(time_no_update = 0,&action)
        trace
        time_to_wait = [ time_no_update, 1 ].max
        self.lock do
          while wait_update time_to_wait
          end
          action.call self unless action.nil?
        end
      end

      def wait_full_update(time_no_update = 0,&action)
        wait_update {
          wait_no_update(time_no_update,&action)
        }
      end

      def wait_condition(time_to_complete = 0,time_no_update = 0,&condition)
        trace
        time = Time.now.to_i
        loop do
          result = wait_no_update(time_no_update) do
            condition.call self
          end
          return result if result

          if time_to_complete > 0 and (Time.now.to_i-time) > time_to_complete
            raise TimeoutError
          end
        end
      end

      def wait_prompt(prompt,time_to_complete = 0,time_no_update = 0,&action)
        expr = prompt.kind_of?(Regexp) ? prompt : (/^#{Regexp.quote(prompt)}$/)
        wait_condition(time_to_complete,time_no_update) {
          line = @area[@cursor.y][0,@cursor.x]
          if line =~ expr
            line = line.clone
            action.call line unless action.nil?
            line
          end
        }
      end

      def wait_cursor_at(point,time_to_complete = 0,time_no_update = 0,&action)
        trace
        wait_condition(time_to_complete,time_no_update) {
          if cursor_at? point
            action.call cursor unless action.nil?
            cursor
          end
        }
      end

      def foreach_newline(time_no_update = nil,&action)
        trace
        with_line_buffer do |_buffer|
          _buffer.each_newline time_no_update , &action
        end
      end
      
      def show(&visualizer)
        if visualizer.nil?
          visualizer = proc { |_line| puts "#{_line}" }
        end
        visualizer.call "size=#{@size.inspect}"
        visualizer.call "cursor=#{@cursor.inspect}"
        visualizer.call "region=#{@scroll_region.inspect}"
        visualizer.call "title=#{@title.inspect}"

        separator = "+#{'-' * @size.x}+"
        visualizer.call separator
        @area.each { |_line| visualizer.call "|#{_line}|" }
        visualizer.call separator
      end

      #
      # Session::AbstractScreen implementation.
      #
      def message(message)
        trace message
      end

      def display(text)
        text = text.to_s
        trace text

        ensure_update do 
          depot = ""
          text.each_byte do |_byte|
            if @special_characters.include? _byte
              process_text depot
              depot = ""
              @special_characters[_byte].call
            else
              depot << _byte
            end
          end
          process_text depot
        end
      end

      def beep
        trace
      end

      def set_lines(array)
        trace

        ensure_update do
          longest = ( array.collect { |_entry| _entry.length } ).max
          reset_size longest, array.size

          set_cursor @cursor
          set_scroll_region @scroll_region

          area = array.collect { |_line| "%-#{longest}s" % _line }
          if area != @area
            @area = area
            signal_update
          end
        end
      end

      def set_cursor(*args)
        target = Pair.new *args
        trace target, @cursor

        ensure_update do
          adjust_cursor_x target.x
          adjust_cursor_y target.y

          @line_start = cursor
          @line_content = nil

          signal_update
        end
      end

      def set_scroll_region(*args)
        region = Pair.new *args
        trace region, @scroll_region

        ensure_update do
          x = [[0, region.x].max, @size.y-1].min
          y = [[x, region.y].max, @size.y-1].min

          scrollRegion = Pair.new(x,y)
          if @scroll_region != scrollRegion
            @scroll_region = scrollRegion
            signal_update
          end
        end
      end

      def scroll_up(number)
        trace number
        number = number.to_i

        ensure_update do
          if number > 0
            if @cursor.y.between? @scroll_region.x, @scroll_region.y
              top = @scroll_region.x
              bottom = @scroll_region.y
            else
              top = 0
              bottom = @size.y - 1
            end
            area = @area[top .. bottom]
            number.times do 
              area.shift
              area.push ' ' * @size.x
            end
            @area[top .. bottom] = area
            signal_update
          end
        end
      end

      def scroll_down(number)
        trace number
        number = number.to_i

        ensure_update do
          if number > 0
            if @cursor.y.between? @scroll_region.x, @scroll_region.y
              top = @scroll_region.x
              bottom = @scroll_region.y
            else
              top = 0
              bottom = @size.y - 1
            end
            area = @area[top .. bottom]
            number.times do 
              area.pop
              area.unshift ' ' * @size.x
            end
            @area[top .. bottom] = area
            signal_update
          end
        end
      end

      def erase(*args)
        region = Pair.new *args
        trace region

        ensure_update do
          number = @size.x * @size.y

          return unless region.x.between?(0,number)
          return unless region.y.between?(region.x+1,number)

          region.x.upto(region.y-1) do |_index|
            @area[_index / @size.x][_index % @size.x,1] = ' '
          end
          signal_update
        end
      end

      def insert_lines(number)
        ensure_update do
          @area[@cursor.y,0] = (0...number).collect { empty_line }
          @area[@size.y..-1] = nil

          signal_update
        end
      end

      def delete_lines(number)
        ensure_update do
          @area[@cursor.y,[number,0].max ] = nil
          @area += (@area.size...@size.y).collect { empty_line }

          signal_update
        end
      end

      def insert_chars(number)
        ensure_update do
          @area[@cursor.y][@cursor.x,0] = ' ' * [number,0].max
          @area[@cursor.y][@size.x..-1] = ''

          signal_update
        end
      end

      def delete_chars(number)
        ensure_update do
          @area[@cursor.y][@cursor.x,[number,0].max ] = ''
          @area[@cursor.y] = "%-#{@size.x}.#{@size.x}s" % @area[@cursor.y]

          signal_update
        end
      end

      def clear
        ensure_update do
          @area = (0...@size.y).collect { empty_line }

          @cursor = Pair.new(0,0)
          @line_start = cursor
          @line_content = nil
          @scroll_region = Pair.new(0,@size.y-1)

          signal_update
        end
      end

      def resize_and_clear(*args)
        ensure_update do
          reset_size *args
          clear
        end
      end

      private 
      #######
      def reset_size(*args)
        @size = Pair.new *args
      end

      def initialize(newline_assumes_return = false)
        @mutex = TSC::Monitor.new
        @update_condition = TSC::Monitor::ConditionVariable.new @mutex
        @newline_condition = TSC::Monitor::ConditionVariable.new @mutex
        @line_buffers = []
        @autowrap = true

        @newline_assumes_return = newline_assumes_return
        reset_size 80, 24
        clear

        @special_characters = Hash[ 
          000 => proc {},
          007 => proc { beep },
          010 => proc { process_backspace },
          011 => proc { process_tab },
          012 => proc { process_newline },
          015 => proc { process_return }
        ]
        @update_counter = 0
        @in_ensure = false
      end

      def signal_update
        @update_counter += 1
      end

      def ensure_update(&block)
        self.lock do
          state = @in_ensure
          @in_ensure = true
          unless state
            @update_counter = 0
          end

          block.call unless block.nil?

          if (state == false) and (@update_counter > 0)
            trace @update_counter
            @update_condition.broadcast
          end
          @in_ensure = state
        end
      end

      def adjust_cursor_x(x)
        @cursor.x = [[0, x].max, @size.x].min
      end

      def adjust_cursor_y(y)
        @cursor.y = [[0, y].max, @size.y].min
      end

      def empty_line
        ' ' * @size.x
      end

      def process_text(text)
        trace text
        return if text.empty?
        
        if @cursor.x == @size.x
          return unless @autowrap == true

          process_return
          process_newline
        end
        number = [@size.x-@cursor.x, text.length].min;

        if @cursor.y < @size.y
          @area[@cursor.y][@cursor.x,number] = text[0,number]
        end
        @cursor.x += number
        remain = text.length - number

        process_text text[number,remain] if remain > 0
        signal_update
      end

      def process_backspace
        x = @cursor.x
        x -= 1 if x == @size.x
        adjust_cursor_x x-1
        signal_update
      end

      def process_tab
        adjust_cursor_x @cursor.x + (TABSTOP - (@cursor.x % TABSTOP))
        signal_update
      end

      def process_return
        trace
        preserve_line
        adjust_cursor_x 0
        @line_start = cursor
        signal_update
      end

      def preserve_line
        if @line_start.y != @cursor.y
          raise "Line number mismatch: #{@line_start.y} vs. #{@cursor.y}"
        end
        if @cursor.x > @line_start.x
          @line_content = (@area[@cursor.y][@line_start.x ... @cursor.x]).clone
        end
      end
      
      def process_newline
        trace
        process_return if @newline_assumes_return == true
        preserve_line
        register_line
        if @cursor.y == @scroll_region.y or @cursor.y == (@size.y - 1)
          scroll_up 1
        else
          adjust_cursor_y @cursor.y + 1
          @line_start = cursor
          signal_update
        end
      end

      def register_line
        unless @line_buffers.empty?
          line = "#{@line_content}"
          @line_buffers.each do |_buffer|
            _buffer.push line
          end
          @newline_condition.broadcast
        end
        @line_content = nil
      end
      
      def with_line_buffer
        trace
        return unless block_given?
        self.lock do
          buffer = LineBuffer.new @newline_condition
          begin
            @line_buffers << buffer
            yield buffer
          ensure
            @line_buffers.delete buffer
          end
        end
      end
    end
  end
end

if $0 != '-e' and $0 == __FILE__ or defined? Test::Unit::TestCase
  require 'test/unit'

  Thread.abort_on_exception = true
  module TSC
    module Session
      class ScreenTest < Test::Unit::TestCase
        def test_size
          assert_equal 80, @screen.size.x, "Wrong screen width"
          assert_equal 24, @screen.size.y, "Wrong screen height"
          area = @screen.lines
          assert_equal @screen.size.y, area.size, "Wrong screen area size"
          @screen.size.y.times do |_line|
            assert_equal @screen.size.x, area[_line].size, "Wrong size of line #{_line}"
          end
        end

        def test_mutation
          cursor = @screen.cursor
          x = cursor.x
          cursor.x = x + 5
          assert_equal x, @screen.cursor.x, "Cursor is mutable"

          size = @screen.size
          x = size.x
          size.x = x + 5
          assert_equal x, @screen.size.x, "Screen size is mutable"

          lines = @screen.lines
          line5 = lines[5]
          lines[5] = line5 + 'abc'
          assert @screen.lines[5] == line5, "Screen area is mutable"

          @screen.set_cursor 0, 5
          @screen.display "abcdef"
          assert @screen.lines[5][0,6] == "abcdef", "Wrong screen content"
          
          @screen.lines[5].swapcase!

          assert @screen.lines[5][0,6] == "abcdef", "Screen area is mutable"
        end

        def test_cursor
          @screen.set_cursor 35, 7
          assert_equal 35, @screen.cursor.x
          assert_equal 7, @screen.cursor.y
          assert_equal true, @screen.cursor_at?(35, 7)
          assert_equal false, @screen.cursor_at?(7, 35)

          @screen.set_cursor -435, @screen.size.y + 8
          assert_equal 0, @screen.cursor.x
          assert_equal @screen.size.y, @screen.cursor.y
          assert_equal true, @screen.cursor_at?(0, @screen.size.y)

          @screen.set_cursor @screen.size.x + 6, -67
          assert_equal @screen.size.x, @screen.cursor.x
          assert_equal 0, @screen.cursor.y
        end

        def test_display
          text = "abcdef"
          @screen.display text

          assert_equal 6, @screen.cursor.x, "Cursor (x) has not moved correctly"
          assert_equal 0, @screen.cursor.y, "Cursor (y) has not moved correctly"

          expected = "%-#{@screen.size.x}.#{@screen.size.x}s" % text
          assert_equal expected, @screen.lines[0], "Wrong line content"

          @screen.display "xyz"
          expected = "%-#{@screen.size.x}.#{@screen.size.x}s" % "#{text}xyz"
          assert_equal expected, @screen.lines[0], "Wrong line content"

          @screen.set_cursor @screen.size.x-3, 0
          @screen.display text

          assert_equal 3, @screen.cursor.x, "Cursor (x) has not moved correctly"
          assert_equal 1, @screen.cursor.y, "Cursor (y) has not moved correctly"

          assert_equal @screen.size.x, @screen.lines[0].size, "Wrong line size"
          assert_equal @screen.size.x, @screen.lines[1].size, "Wrong line size"

          expected = "%-#{@screen.size.x}.#{@screen.size.x}s" % "#{text}xyz"
          expected[(expected.length-3) ... expected.length] = text[0 ... 3]
          assert_equal expected, @screen.lines[0], "Wrong line content"
          assert_equal "def ", @screen.lines[1][0,4], "Wrong line content"

          @screen.set_cursor @screen.size.x-3, @screen.size.y-1
          @screen.display text
          assert_equal Pair[3,@screen.size.y-1], @screen.cursor, "Wrong cursor position"
          assert_equal "def ", @screen.lines[0][0,4], "Wrong line content"
          assert_equal "def ", @screen.lines[@screen.size.y-1][0,4], "Wrong line content"
          expected = "%#{@screen.size.x}.#{@screen.size.x}s" % "abc"
          assert_equal expected, @screen.lines[@screen.size.y-2], "Wrong line content"
        end

        def test_display_in_last_line
          @screen.set_cursor 0, 23
          @screen.display "abcd"
          @screen.display "z"
          assert_equal "abcdz", @screen.lines[23][0,5]
        end

        def test_display_null_chars
          @screen.display "\000abc\000d\007ef"
          assert_equal Pair[6,0], @screen.cursor, "Wrong cursor position"
          assert_equal "abcdef ", @screen.lines[0][0,7], "Wrong line content"
        end

        def test_tab_stops
          expected = "a       abc     abcdefg abcdefgh        zzz "
          @screen.display "a\tabc\tabcdefg\tabcdefgh\tzzz"
          assert_equal expected, @screen.lines[0][0,expected.length], "Wrong line content"
          assert_equal Pair[expected.length-1,0], @screen.cursor, "Wrong cursor position"
        end

        def test_tab_not_destructive
          @screen.display "abc\r\tdef"
          assert_equal Pair[11,0], @screen.cursor, "Wrong cursor position"
          assert_equal "abc     def ", @screen.lines[0][0,12], "Wrong line content"
        end

        def test_return
          @screen.set_cursor 4, 15
          @screen.display "abcdef\rzzz"
          assert_equal Pair[3,15], @screen.cursor, "Wrong cursor position"
          assert_equal "zzz abcdef ", @screen.lines[15][0,11], "Wrong line content"
        end

        def test_newline
          @screen.display "abcdef\n"
          assert_equal Pair[6,1], @screen.cursor, "Wrong cursor position"
          assert_equal "abcdef ", @screen.lines[0][0,7], "Wrong line content"
          @screen.display "\rzzzzzzz\n\r"
          assert_equal Pair[0,2], @screen.cursor, "Wrong cursor position"
          assert_equal "zzzzzzz ", @screen.lines[1][0,8], "Wrong line content"
          @screen.set_cursor 0, 23
          @screen.display "querty\nqqq"
          assert_equal Pair[9,23], @screen.cursor, "Wrong cursor position"
          assert_equal "zzzzzzz ", @screen.lines[0][0,8], "No scroll"
          assert_equal "querty ", @screen.lines[22][0,7], "No scroll"
          assert_equal "      qqq ", @screen.lines[23][0,10], "No scroll"
        end

        def test_backspace
          @screen.display "abcdef\b"
          assert_equal Pair[5,0], @screen.cursor, "Wrong cursor position"
          assert_equal "abcdef ", @screen.lines[0][0,7], "Wrong line content"
          @screen.display "zzz"
          assert_equal Pair[8,0], @screen.cursor, "Wrong cursor position"
          assert_equal "abcdezzz ", @screen.lines[0][0,9], "Wrong line content"
        end

        def test_display_in_last_position
          @screen.set_cursor 78, 0
          @screen.display "aaa"
          assert_equal Pair[1,1], @screen.cursor, "Wrong cursor position"

          @screen.set_cursor 78, 0
          @screen.display "aa"
          assert_equal Pair[80,0], @screen.cursor, "Wrong cursor position"
          @screen.display "a"
          assert_equal Pair[1,1], @screen.cursor, "Wrong cursor position"
        end

        def test_backspace_in_last_position
          @screen.set_cursor 78, 0
          @screen.display 'aa'
          assert_equal Pair[80,0], @screen.cursor, "Wrong cursor position"
          @screen.display "\b"
          assert_equal Pair[78,0], @screen.cursor, "Wrong cursor position"
        end

        def test_scroll_region
          @screen.set_scroll_region 1, 7
          assert_equal Pair[1,7], @screen.scroll_region, "Wrong scroll region"

          @screen.set_scroll_region -1, 14
          assert_equal Pair[0,14], @screen.scroll_region, "Wrong scroll region"

          @screen.set_scroll_region 34, 15
          assert_equal Pair[23,23], @screen.scroll_region, "Wrong scroll region"

          @screen.set_scroll_region -3, -7
          assert_equal Pair[0,0], @screen.scroll_region, "Wrong scroll region"
        end

        def test_set_lines
          @screen.set_lines ["aaaaa","bbbbbbbbbb","ccc"]
          assert_equal Pair[10,3], @screen.size, "Wrong screen size"
          assert_equal Pair[0,0], @screen.cursor, "Wrong cursor position"
          assert_equal Pair[0,2], @screen.scroll_region, "Wrong scroll region"
          assert_equal "aaaaa     ", @screen.lines[0], "Wrong line content"
          assert_equal "bbbbbbbbbb", @screen.lines[1], "Wrong line content"
          assert_equal "ccc       ", @screen.lines[2], "Wrong line content"
        end

        def test_wait_no_update
          thread = Thread.new {
            sleep 1
            @screen.display "a"
            sleep 1
            @screen.display "a"
            sleep 3
            @screen.display "a"
          }
          @screen.wait_no_update 2 do
            @result = @screen.lines[0].strip
          end
          thread.kill
          assert_equal "aa", @result
        end

        def test_wait_prompt
          @screen.display 'Login: '
          assert_equal 'Login: ', @screen.wait_prompt('Login: ',1)
          Thread.new {
            sleep 1
            @screen.set_cursor 3, 12
            @screen.display 'Password: '
          }
          assert_equal '   Password: ', @screen.wait_prompt(/word: $/,3)
        end

        def test_wait_cursor
          Thread.new {
            sleep 1
            @screen.set_cursor 7, 10
          }
          assert_equal Pair[7,10], @screen.wait_cursor_at([7, 10],3)
        end

        def test_timing
          Thread.new {
            sleep 1
            @screen.display "aaa"
            sleep 3
          }
          @screen.wait_prompt "aaa", 3
        end

        def test_line_stream_top
          @screen.newline_assumes_return = true
          Thread.new {
            sleep 1
            @screen.display "aaa\n"
            @screen.display "bbb\nccc\n"
            @screen.display "end\n"
          }
          array = []
          @screen.foreach_newline 2 do |_line|
            if _line == "end"
              false
            else
              array << _line
              true
            end
          end
          assert_equal ["aaa", "bbb", "ccc"], array
        end

        def test_line_stream_bottom
          @screen.newline_assumes_return = true
          Thread.new {
            sleep 1
            @screen.set_cursor 0, 23
            @screen.display "aaa\n"
            @screen.display "bbb\nccc\n"
            @screen.display "end\n"
          }
          array = []
          @screen.foreach_newline 2 do |_line|
            unless _line == "end"
              trace "adding", _line
              array << _line
            end
          end
          assert_equal ["aaa", "bbb", "ccc"], array
        end

        def test_line_stream_scroll_away
          @screen.newline_assumes_return = true
          Thread.new {
            sleep 1
            @screen.set_cursor 0, 15
            @screen.display "aaa\n"
            @screen.display "bbb\nccc\n"
            30.times do
              @screen.display "zzz\n"
            end
            @screen.display "end\n"
          }
          array = []
          @screen.foreach_newline 2 do |_line|
            unless _line == "end"
              trace "adding", _line
              array << _line
            end
          end
          assert_equal 33, array.size
          assert_equal ["aaa", "bbb", "ccc"], array[0,3]
        end

        def test_line_stream_long_line
          @screen.newline_assumes_return = true
          Thread.new {
            sleep 1
            100.times do
              @screen.display "a"
            end
            @screen.display "\n"
            @screen.display "end\n"
          }
          array = []
          result = @screen.foreach_newline 2 do |_line|
            unless _line == "end"
              trace "adding", _line
              array << _line
            end
          end
          assert_equal true, result
          assert_equal 2, array.size
          assert_equal "a" * @screen.size.x, array[0]
          assert_equal "a" * (100 - @screen.size.x), array[1]
        end

        def test_line_stream_timeout
          @screen.newline_assumes_return = true
          thread = Thread.new {
            sleep 1
            @screen.display "aaa\n"
            sleep 1
            @screen.display "bbb\n"
            sleep 3
            @screen.display "ccc\n"
          }
          array = []
          result = @screen.foreach_newline 2 do |_line|
            if _line == "end"
              false
            else
              array << _line
              true
            end
          end
          thread.kill 
          assert_equal false, result
          assert_equal ["aaa", "bbb" ], array
        end

        def test_insert_lines
          @screen.newline_assumes_return = true
          size = @screen.size

          @screen.display "#{'a'*20}\n"
          @screen.display "#{'b'*20}\n"
          @screen.display "#{'c'*20}\n"
          @screen.set_cursor 0, @screen.size.y-2
          @screen.display "#{'d'*20}\n"

          assert true, @screen.lines[-1].strip.empty?

          @screen.set_cursor 0, 0
          lines = @screen.lines
          @screen.insert_lines -2
          assert_equal size, @screen.size
          assert_equal lines, @screen.lines

          @screen.insert_lines 1
          assert_not_equal lines, @screen.lines
          assert_equal size, @screen.size
          assert_equal 'a' * 20, @screen.lines[1].strip
          assert_equal 'd' * 20, @screen.lines[-1].strip

          @screen.insert_lines 2
          assert_equal size, @screen.size
          assert true, @screen.lines[-1].strip.empty?
          assert_equal 'a' * 20, @screen.lines[3].strip
          assert_equal 'c' * 20, @screen.lines[5].strip

          @screen.insert_lines 200
          assert_equal size, @screen.size
          assert_equal((0...size.y).collect{' '*size.x},@screen.lines)
        end

        def test_delete_lines
          @screen.newline_assumes_return = true
          size = @screen.size

          @screen.display "#{'a'*20}\n"
          @screen.display "#{'b'*20}\n"
          @screen.display "#{'c'*20}\n"
          @screen.set_cursor 0, @screen.size.y-2
          @screen.display "#{'d'*20}\n"

          assert true, @screen.lines[-1].strip.empty?

          @screen.set_cursor 0, 3
          lines = @screen.lines
          @screen.delete_lines -2
          assert_equal size, @screen.size
          assert_equal lines, @screen.lines

          @screen.delete_lines size.y-5
          assert_equal size, @screen.size
          assert_equal 'd' * 20, @screen.lines[3].strip

          @screen.set_cursor 0, 1
          @screen.delete_lines 2
          assert_equal size, @screen.size
          assert_equal 'a' * 20, @screen.lines[0].strip
          assert_equal 'd' * 20, @screen.lines[1].strip

          @screen.set_cursor 0, 0
          @screen.delete_lines 750
          assert_equal size, @screen.size
          assert_equal((0...size.y).collect{' '*size.x},@screen.lines)
        end

        def test_insert_chars
          size = @screen.size

          @screen.display "#{'a'*20}\n"
          @screen.set_cursor 3, 0
          @screen.insert_chars 5
          assert_equal size, @screen.size
          assert_equal "aaa#{' '*5}#{'a'*17}#{' '*(size.x-25)}", @screen.lines[0]

          line0 = @screen.lines[0]
          @screen.insert_chars -1
          assert_equal line0, @screen.lines[0]

          @screen.set_cursor 0, 1
          @screen.display "#{'a'*10}"
          @screen.display "#{'b'*10}"

          @screen.set_cursor 10, 1
          @screen.insert_chars size.x - 20
          assert_equal "#{'a'*10}#{' '*(size.x-20)}#{'b'*10}", @screen.lines[1]

          @screen.insert_chars 9
          assert_equal "#{'a'*10}#{' '*(size.x-11)}b", @screen.lines[1]

          @screen.set_cursor 0, 1
          @screen.insert_chars 400
          assert_equal size.x, @screen.lines[1].size
          assert true, @screen.lines[1].strip.empty?
        end

        def test_delete_chars
          @screen.display "#{'a'*20}"
          @screen.display "#{'b'*20}"

          @screen.set_cursor 3, 0
          @screen.delete_chars 17
          assert_equal "aaa#{'b'*20}#{' '*(@screen.size.x-23)}", @screen.lines[0]

          @screen.set_cursor 0, 0
          @screen.delete_chars 712
          assert_equal ' '*@screen.size.x, @screen.lines[0]
        end

        def test_line
          @screen.display "abc\ncda\nzzz"
          @screen.set_cursor 0, @screen.size.y - 1
          @screen.display 'AAA'

          assert_equal 'cda', @screen.line(1).strip
          assert_equal 'AAA', @screen.line(-1).strip

          assert_equal '', @screen.line(@screen.size.y)
        end

        def test_line_from_cursor
          @screen.newline_assumes_return = true

          @screen.display "aaa\nbbb\nccc"
          @screen.set_cursor 0, @screen.size.y - 3
          @screen.display "AAA\nBBB\nCCC"

          @screen.set_cursor 10, 1
          assert_equal 'aaa', @screen.line_from_cursor(-1).strip
          assert_equal 'bbb', @screen.line_from_cursor(0).strip
          assert_equal 'ccc', @screen.line_from_cursor(1).strip

          assert_equal 'AAA', @screen.line_from_cursor(@screen.size.y - 4).strip
          assert_equal '', @screen.line_from_cursor(@screen.size.y - 1)
          assert_equal '', @screen.line_from_cursor(@screen.size.y)

          assert_equal '', @screen.line_from_cursor(-2)
        end

        def test_line_upto_cursor
          @screen.newline_assumes_return = true
          @screen.display "aaa\nabcdefg\nbbb"
          @screen.set_cursor 5, 1

          assert_equal 'abc', @screen.line_upto_cursor(-2).strip
          assert_equal 'abcde', @screen.line_upto_cursor(0).strip
          assert_equal 'abcdef', @screen.line_upto_cursor(1).strip
        end

        def test_lines_upto_cursor_since
          @screen.newline_assumes_return = true
          @screen.display "aaa\nbbb\nccc\nddd\n@ "

          assert_equal [ 'ccc', 'ddd' ], @screen.lines_upto_cursor_since(%r{^bbb\s+$}).map { |_line| _line.strip}
          assert_equal [ 'aaa', 'bbb', 'ccc', 'ddd' ], @screen.lines_upto_cursor_since(%r{zzz}).map { |_line| _line.strip}
          assert_equal [], @screen.lines_upto_cursor_since(%r{ddd})

          assert_equal [ 'ddd' ], @screen.lines_upto_cursor_since(%r{ccc}).map { |_line| _line.strip}
          assert_equal [ 'ddd' ], @screen.lines_upto_cursor_since { |_line| _line.strip!; _line == 'ccc' }

          assert_equal [ 'ddd' ], @screen.lines_upto_cursor_since(%r{zzz},%r{ccc}).map { |_line| _line.strip}
          assert_equal [ 'ddd' ], @screen.lines_upto_cursor_since(%r{aaa},%r{ccc}).map { |_line| _line.strip}
          assert_equal [ 'ddd' ], @screen.lines_upto_cursor_since(%r{ccc},%r{aaa}).map { |_line| _line.strip}
        end

        include TSC::Trace

        def debug
          false
        end

        def setup
          @screen = Session::Screen.new
          @result = nil
        end

        def teardown
          @screen = nil
        end
      end
    end
  end
end
