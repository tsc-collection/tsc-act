# Copyright (c) 2006, Gennady Bystritsky <bystr@mac.com>
# 
# Distributed under the MIT Licence.
# This is free software. See 'LICENSE' for details.
# You must read and accept the license prior to use.

require 'tsc/session/vt100-emulator.rb'
require 'tsc/session/screen.rb'

module TSC
  module Session
    module EmulatorProvider
      def emulator
        emulator = TSC::Session::Vt100Emulator.new TSC::Session::Screen.new
        emulator.tolerant = false
        emulator
      end
    end
  end
end

