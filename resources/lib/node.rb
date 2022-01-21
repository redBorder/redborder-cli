class NodeCmd < CmdParse::Command
  def initialize
    super('node')
    short_desc('Manage node actions and values')
    add_command(NodeListCmd.new, default: true)
    add_command(NodeExecuteCmd.new, default: false)
  end
end

class NodeListCmd < CmdParse::Command
  def initialize
    super('list', takes_commands: false)
    short_desc('List nodes from cluster')
    options.on('-a', '--alphabetically', 'Alphabetically ordered') { $parser.data[:alphabetically_ordered] = true }
    options.on('-c', '--compact', 'Compact format') { $parser.data[:compact_format] = true }
    options.on('-x', '--extend', 'Extended information') { $parser.data[:extended_format] = true }
  end

  def execute()

    utils = Utils.instance
    nodes = utils.get_consul_members

    if !nodes.empty? 
      # order alphabetically
      if ($parser.data[:alphabetically_ordered])
        nodes = nodes.sort{|a,b| (a||"zzzzzzzz") <=> (b||"zzzzzzzz")}
      end

      # show output in one line or multiple
      if ($parser.data[:compact_format])
        puts nodes.join(" ").strip()
      else 
        nodes.each do |node|
          puts node
          if  $parser.data[:extended_format]
            mode = `serf members -status alive -name=#{node} -format=json | jq -r '.members[].tags.mode'`
            puts "  mode : #{mode}"
          end
        end
      end
    else
      puts "Error: consul service not available"
    end
  end
end

class NodeExecuteCmd < CmdParse::Command

  def initialize
    super('execute', takes_commands: false)
    short_desc('iexecute command in node')
  end

  def execute(node,*cmd)
    utils = Utils.instance
    nodes = []
   
    nodes = utils.check_nodes(node)
    if (nodes.count == 0)
      cmd.insert(0, node)
      nodes << Socket.gethostname.split(".").first
    end

    nodes.each do |n|
      puts "##############################################"
      puts "# Node: #{n}"
      puts "##############################################"
      utils.remote_cmd(n, cmd)
    end
  end

end

$parser.add_command(NodeCmd.new)

