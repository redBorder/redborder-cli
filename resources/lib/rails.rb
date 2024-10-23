
class RailsCmd < CmdParse::Command
  def initialize
    super('rails')
    short_desc('Rails actions and values')
    add_command(RailsConsoleCmd.new, default: true)
  end
end

class RailsConsoleCmd < CmdParse::Command
  def initialize
    super('console', takes_commands: false)
    short_desc('Start rails console')
  end

  def execute()
    system("/usr/lib/redborder/bin/rb_rails_console.sh")
  end
end

$parser.add_command(RailsCmd.new)

