=begin
  vim: sw=2:
  Copyright (c) 2011, Quest Software, http://www.quest.com
  
  ALL RIGHTS RESERVED.
  
  This software is the confidential and proprietary information of
  Quest Software Inc. ("Confidential Information"). You shall not
  disclose such Confidential Information and shall use it only in
  accordance with the terms of the license agreement you entered
  into with Quest Software Inc.
  
  QUEST SOFTWARE INC. MAKES NO REPRESENTATIONS OR
  WARRANTIES ABOUT THE SUITABILITY OF THE SOFTWARE,
  EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED
  TO THE IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS
  FOR A PARTICULAR PURPOSE, OR NON-INFRINGEMENT. QUEST
  SOFTWARE SHALL NOT BE LIABLE FOR ANY DAMAGES
  SUFFERED BY LICENSEE AS A RESULT OF USING, MODIFYING
  OR DISTRIBUTING THIS SOFTWARE OR ITS DERIVATIVES.
  
  Author: Gennady Bystritsky (gennady.bystritsky@quest.com)
=end

module TSC
  module Session
    class UnixTerminalArranger
      attr_reader :user, :password

      def initialize(provider)
        @user = provider.user
        @password = provider.password
        @prompt = Regexp.new(provider.prompt || "[$%#>]\s+$")
      end

      def arrange_terminal(terminal)
        terminal.tap do
          Arranger.new(terminal, @prompt).tap { |_arranger|
            _arranger.login(user, password)
            _arranger.setup_terminal_size
            _arranger.setup_terminal_type
          }
        end
      end

      class Arranger
        attr_reader :terminal, :prompt

        def initialize(terminal, prompt)
          @terminal = terminal
          @prompt = prompt
        end

        def login(user, password)
          terminal.screen.lock do
            terminal.screen.wait_prompt %r{ogin:\s*}, 60
            terminal.typein "#{user}\n"

            terminal.screen.wait_prompt %r{assword:\s*}, 30
            terminal.typein "#{password}\n"

            terminal.screen.wait_prompt prompt, 30
          end
        end

        def setup_terminal_size
          terminal.screen.lock do
            terminal.screen.wait_prompt prompt, 60
            terminal.typein "stty rows #{terminal.screen.size.y} cols #{terminal.screen.size.x}\n"

            terminal.screen.wait_prompt prompt, 10
            terminal.typein "LINES=#{terminal.screen.size.y} export LINES\n"

            terminal.screen.wait_prompt prompt, 10
            terminal.typein "COLUMNS=#{terminal.screen.size.x} export COLUMNS\n"

            terminal.screen.wait_prompt prompt, 10
            terminal.typein "COLS=#{terminal.screen.size.x} export COLS\n"

            terminal.screen.wait_prompt prompt, 10
          end
        end

        def setup_terminal_type
          terminal.screen.lock do
            terminal.screen.wait_prompt prompt, 60
            terminal.typein "TERM='#{terminal.term}' export TERM\n"

            terminal.screen.wait_prompt prompt, 10
          end
        end
      end
    end
  end
end

if $0 == __FILE__
  require 'test/unit'
  require 'mocha'

  module TSC
    module Session
      class UnixTerminalArrangerTest < Test::Unit::TestCase
        def setup
        end
      end
    end
  end
end
