class SetupCmd < CmdParse::Command
  def initialize
    super('setup')
    short_desc('Manage configuration')
    add_command(SetupWizardCmd.new, default: true)
  end
end

class SetupWizardCmd < CmdParse::Command
  def initialize
    super('wizard', takes_commands: false)
    short_desc('Start setup wizard')
  end

  def execute()
    utils = Utils.instance
    system("rb_setup_wizard")
  end
end

$parser.add_command(SetupCmd.new)

