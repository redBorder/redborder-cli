require 'net/http'
require 'uri'
require 'json'

class NodeCmd < CmdParse::Command
  def initialize
    super('node')
    short_desc('Manage node actions and values')
    add_command(NodeListCmd.new, default: true)
  end
end

class NodeListCmd < CmdParse::Command
  def initialize
    super('list', takes_commands: false)
    short_desc('List nodes from cluster')
    options.on('-x', '--extend', 'Extended information') { puts 'Extended information' }
  end

  def execute()

    uri = URI.parse("http://localhost:8500/v1/agent/members")
    response = Net::HTTP.get_response(uri)
    if response.code == "200"
      ret = JSON.parse(response.body)
      ret.each do |member|
        puts member["Name"]
      end
    else
      puts "Error: consul service not available"
    end

    # response.code
    # response.body
    #puts "Hello #{name}, options: #{opt.join(', ')}"
  end
end

$parser.add_command(NodeCmd.new)

