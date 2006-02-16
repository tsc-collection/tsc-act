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


require 'demo/mvs/tso-logoff.rb'
require 'tsc/progress.rb'
require 'session/mvs/pts-info.rb'
require 'session/mvs/tso.rb'

module Demo
  module Mvs
    class ItemAction < ::Demo::Mvs::LogoffAction
      def perform
	raise "No items specified" if ARGV.empty?

	ARGV.map { |_parameter|
	  item = Session::Mvs::PtsInfo.new _parameter
	  TSC::Progress.new "Obtaining details for #{item.name}" do |_progress|
	    @body = tso.refresh_item(item) {
	      _progress.print unless verbose
	    }
	  end
	  [ item, @body ]
	}.each do |_item|
	  puts "#{_item.slice(0).name}:"
	  _item.slice(1).each do |_line|
	    puts "  > #{_line}"
	  end
	end
      end
    end
  end
end
