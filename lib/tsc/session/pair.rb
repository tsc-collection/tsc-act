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

module TSC
  module Session
    class Pair
      class << self
        def [](*args)
          self.new *args
        end
      end

      attr_accessor :x, :y

      def initialize(*args)
        @x, @y = *normalize(*args)
      end

      def to_a
        [ x, y ]
      end

      def ==(*args)
        self.to_a == normalize(*args)
      end

      private
      #######
      def normalize(*args)
        case args.size
          when 0 
            [0, 0]
          when 1
            args = Array(args.first)
            raise ArgumentError if args.size == 1
            normalize *args
          when 2
            args.map { |_arg| _arg.to_i }
          else 
            raise ArgumentError
        end
      end
    end
  end
end

if $0 != '-e' and $0 == __FILE__ or defined? Test::Unit::TestCase
  require 'test/unit'

  module TSC
    module Session
      class PairTest < Test::Unit::TestCase
        def test_create_form_x_y
          pair = Pair[3,4]

          assert_equal 3, pair.x
          assert_equal 4, pair.y
        end

        def test_create_from_other_pair
          p1 = Pair[7,10]
          p2 = Pair[p1]

          assert_equal 7, p2.x
          assert_equal 10, p2.y
        end

        def test_create_from_array
          pair = Pair.new [5, 9]

          assert_equal 5, pair.x
          assert_equal 9, pair.y
        end

        def test_create_empty
          pair = Pair.new
          assert_equal 0, pair.x
          assert_equal 0, pair.y
        end

        def test_equal_pair
          pair = Pair[21,44]

          assert_equal Pair[21,44], pair
          assert_not_equal Pair[44,21], pair
          assert_equal pair, Pair[21,44]
          assert_not_equal pair, Pair[44,21]
        end

        def test_equal_array
          pair = Pair[21,44]

          assert_equal pair, [21, 44]
          assert_not_equal pair, [44, 21]
        end

        def test_wrong_arguments
          assert_raises(ArgumentError) { Pair.new 1 }
          assert_raises(ArgumentError) { Pair.new 1, 2, 3 }
          assert_raises(NoMethodError) { Pair.new [], [] }
        end

        def test_to_a
          assert_equal [8, 9], Pair[8,9].to_a
          assert_not_equal [8, 9], Pair[9,8].to_a
        end
      end
    end
  end
end

