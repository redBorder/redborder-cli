
class ZookeeperCmd < CmdParse::Command
  def initialize
    super('zookeeper')
    short_desc('Zookeeper actions and values')
    add_command(ZookeeperStatusCmd.new, default: true)
    add_command(ZookeeperCleanCmd.new, default: false)
  end
end

class ZookeeperStatusCmd < CmdParse::Command
  def initialize
    super('status', takes_commands: false)
    short_desc('shows status of zookeeper service')
  end

  def execute()
    system("/usr/bin/zkServer.sh status")
  end
end

class ZookeeperCleanCmd < CmdParse::Command
  def initialize
    super('clean', takes_commands: false)
    short_desc('clean the zookeeper data')
    options.on('-k', '--kafka', 'Clean kafka') { $parser.data[:clean_kafka] = true  }
    options.on('-f', '--force', 'Force clean') { $parser.data[:force_clean] = true  }
    options.on('-c', '--consumer', 'Delete Consumer data') { $parser.data[:delete_consumer] = true  }
    options.on('-d', '--druid', 'Delete druid data') { $parser.data[:delete_druid] = true  }
    options.on('-p', '--partitions', 'Reassign partitions') { $parser.data[:reassign_partitions] = true  }
  end

  def execute()
    utils = Utils.instance
    service_stop_cmd = ServiceStopCmd.new
    service_start_cmd = ServiceStartCmd.new
    nodes = []

    if (not $parser.data[:force_clean])
      print "Are you sure you want to clean zookeeper data (y/N)? "
      answer = STDIN.gets.chomp
      if ( answer != "y" and answer != "Y")
        exit
      end
    end

    nodes = utils.check_nodes("all")

    puts "stopping chef-client in all nodes"
    service_stop_cmd.execute("all","chef-client")
    puts "stopping services in all nodes"
    service_stop_cmd.execute("all","druid-realtime","druid-indexer","druid-overlord","druid-coordinator","druid-historical","druid-broker","redborder-monitor","webui","f2k","n2klocd","freeradius","redborder-social","nmspd","snmpd","logstash","kafka", "f2k", "sfacctd")
    puts "stopping zookeeper in all nodes"
    service_stop_cmd.execute("all","zookeeper","zookeeper2")
 

    puts "deleting all zookeeper data on disk"
    nodes.each do |n|
        utils.remote_cmd(n, "rm -rf /tmp/zookeeper/version-2/* &>/dev/null")
        utils.remote_cmd(n, "rm -rf /tmp/zookeeper2/version-2/* &>/dev/null")
    end
    
    if $parser.data[:clean_kafka]
        puts "deleting kafka data on disk"
        nodes.each do |n|
            utils.remote_cmd(n, "rm -rf /tmp/kafka/* &>/dev/null")
        end
    end

    puts "start zookeeper service"
    service_start_cmd.execute("all", "zookeeper","zookeeper2")
    sleep(10)
    puts "start kafka service"
    service_start_cmd.execute("all", "kafka")
    sleep(10)
    # TODO : create topics via rbcli command
    puts "start kafka service"
    puts "creating kafka topics"
    utils.remote_cmd(Socket.gethostname.split(".").first,"/usr/lib/redborder/bin/rb_create_topics")
    if $parser.data[:reassign_partitions]
      puts "calculating kafka topics partitions and assign them"
      utils.remote_cmd(Socket.gethostname.split(".").first,"/usr/lib/redborder/bin/rb_reassign_partitions -de")
    end

    if $parser.data[:delete_druid]
      puts "delete druid data in zookeeper"
      system("echo \"deleteall /druid\" | /usr/bin/zkCli.sh -server zookeeper.service &>/dev/null")
    end
    if $parser.data[:delete_consumer]
      puts "delete consumer data in zookeeper"
      system("echo \"deleteall /consumers\" | /usr/bin/zkCli.sh -server zookeeper.service &>/dev/null") if $parser.data[:delete_consumer]
    end

    service_start_cmd.execute("all", "chef-client")
  end

end


$parser.add_command(ZookeeperCmd.new)

