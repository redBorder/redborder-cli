class TestCmd < CmdParse::Command
  def initialize
    super('test')
    short_desc('Short description of command')
    add_command(TestSubCmd.new)
  end
end

class TestSubCmd < CmdParse::Command
  def initialize
    super('sub', takes_commands: false)
    options.on('-x', '--example', 'Example option') { puts 'example' }
  end

  def execute(name, *opt)
    puts "Hello #{name}, options: #{opt.join(', ')}"
  end
end

#$parser.add_command(TestCmd.new)

