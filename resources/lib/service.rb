require 'chef'

class ServiceCmd < CmdParse::Command
  def initialize
    super('service')
    short_desc('Manage service actions and values')
    add_command(ServiceListCmd.new, default: true)
    add_command(ServiceEnableCmd.new, default: false)
    add_command(ServiceDisableCmd.new, default: false)
    add_command(ServiceStartCmd.new, default: false)
    add_command(ServiceStopCmd.new, default: false)
  end
end

class ServiceListCmd < CmdParse::Command
  RESET = "\033[0m"
  RED = "\033[31m"
  GREEN = "\033[32m"
  YELLOW = "\033[33m"

  def initialize
    $parser.data[:show_runtime] = false
    $parser.data[:no_color] = false
    super('list', takes_commands: false)
    short_desc('List services from node')
    options.on('-r', '--runtime', 'Show runtime') { $parser.data[:show_runtime] = true }
    options.on('-n', '--no-color', 'Print without colors') { $parser.data[:no_color] = true }
  end

  def execute()
    utils = Utils.instance
    node_name = Socket.gethostname.split(".").first
    node = utils.get_node(node_name)

    unless node
      puts 'ERROR: Node not found!'
      return
    end

    # Set colors
    if $parser.data[:no_color]
      red, green, yellow, reset = ''
    else
      red, green, yellow, reset = RED, GREEN, YELLOW, RESET
    end

    services = node.attributes['redborder']['services'] ||  []
    systemd_services = node.attributes['redborder']['systemdservices'] || []
    systemctl_services = []
    not_enable_services = []

    services.each do |service, enabled|
      not_enable_services.push(service) unless enabled

      if systemd_services[service]
        not_enable_services.concat(systemd_services[service]) unless services[service] # Some 'systemd services' needs to be included even if not in 'services'. I.e. minio
        systemctl_services.concat(systemd_services[service])
      end
    end
    not_enable_services.uniq!

    # Counters
    running = 0
    stopped = 0
    errors = 0

    # Paint service list
    if $parser.data[:show_runtime]
      printf("================================= Services ==================================\n")
      printf("%-33s %-33s %-10s\n", "Service", "Status(#{node_name})", "Runtime")
      printf("-----------------------------------------------------------------------------\n")
    else
      printf("=========================== Services ============================\n")
      printf("%-33s %-10s\n", "Service", "Status(#{node_name})")
      printf("-----------------------------------------------------------------\n")
    end

    systemctl_services.uniq.sort.each do |systemd_service|
      if system("systemctl status #{systemd_service} &>/dev/null")
        ret = "running"
        running = running + 1
        runtime = `systemctl status #{systemd_service} | grep 'Active:' | awk '{for(i=9;i<=NF;i++) printf $i " "; print ""}'`.strip
        if $parser.data[:show_runtime]
          printf("%-33s #{green}%-33s#{reset}%-10s\n", "#{systemd_service}:", ret, runtime)
        else
          printf("%-33s #{green}%-10s#{reset}\n", "#{systemd_service}:", ret)
        end
      elsif not_enable_services.include?systemd_service
        ret = "not running"
        stopped = stopped + 1
        runtime = "N/A"
        if $parser.data[:show_runtime]
          printf("%-33s #{yellow}%-33s#{reset}%-10s\n", "#{systemd_service}:", ret, runtime)
        else
          printf("%-33s #{yellow}%-10s#{reset}\n", "#{systemd_service}:", ret)
        end
      else
        ret = "not running!!"
        errors = errors + 1
        runtime = "N/A"
        if $parser.data[:show_runtime]
          printf("%-33s #{red}%-33s#{reset}%-10s\n", "#{systemd_service}:", ret, runtime)
        else
          printf("%-33s #{red}%-10s#{reset}\n", "#{systemd_service}:", ret)
        end
      end
    end

    if $parser.data[:show_runtime]
      printf("-----------------------------------------------------------------------------\n")
    else
      printf("-----------------------------------------------------------------\n")
    end
    printf("%-33s %-10s\n","Total:", systemctl_services.count)
    if $parser.data[:show_runtime]
      printf("-----------------------------------------------------------------------------\n")
    else
      printf("-----------------------------------------------------------------\n")
    end
    printf("Running: #{running}  /  Stopped: #{stopped}  /  Errors: #{errors}\n\n")
  end
end

class ServiceEnableCmd < CmdParse::Command
  def initialize
    $parser.data[:all_services] = false
    super('enable', takes_commands: false)
    short_desc('Enable service from node')
  end

  def execute(node, service=nil)
    nodes = []
    utils = Utils.instance

    nodes = utils.check_nodes(node)
    if (nodes.count == 0)
      service = node
      nodes << Socket.gethostname.split(".").first 
    end

    nodes.each do |n|
      node = utils.get_node(n)

      unless node
        puts "ERROR: Node not found!"
        next
      end

      services = node.attributes['redborder']['services'] || []
      systemd_services = node.attributes['redborder']['systemdservices']
    
      group_of_the_service = systemd_services[service]
      services_with_same_group = systemd_services.select{|service,group| group == group_of_the_service }.keys || []

      role = Chef::Role.load(n)
      role.override_attributes["redborder"]["services"] = {} if !role.override_attributes["redborder"].include? "services" # Initialize services in case do not exists

      # save info at the node too
      node.override!["redborder"]["services"] = {} if node["redborder"]["services"].nil?
      node.override!["redborder"]["services"]["overwrite"] = {} if node["redborder"]["services"]["overwrite"].nil?
      
      services_with_same_group.each do |s|
        role.override_attributes["redborder"]["services"][s] = true
        node.override!["redborder"]["services"]["overwrite"][s] = true
        puts "#{s} enabled on #{n}"
      end
      role.save
    end
  end
end

class ServiceDisableCmd < CmdParse::Command
  def initialize
    $parser.data[:all_services] = false
    super('disable', takes_commands: false)
    short_desc('Disable service from node')
  end

  def execute(node, service=nil)
    nodes = []
    utils = Utils.instance

    nodes = utils.check_nodes(node)
    if (nodes.count == 0)
      service = node
      nodes << Socket.gethostname.split(".").first 
    end

    nodes.each do |n|
      node = utils.get_node(n)

      unless node
        puts "ERROR: Node not found!"
        next
      end

      services = node.attributes['redborder']['services'] || []
      systemd_services = node.attributes['redborder']['systemdservices']

      group_of_the_service = systemd_services[service]
      services_with_same_group = systemd_services.select{|service,group| group == group_of_the_service }.keys || []

      role = Chef::Role.load(n)
      role.override_attributes["redborder"]["services"] = {} if !role.override_attributes["redborder"].include? "services" # Initialize services in case do not exists

      # save info at the node too
      node.override!["redborder"]["services"] = {} if node["redborder"]["services"].nil?
      node.override!["redborder"]["services"]["overwrite"] = {} if node["redborder"]["services"]["overwrite"].nil?

      services_with_same_group.each do |s|
         role.override_attributes["redborder"]["services"][s] = false
         node.override!["redborder"]["services"]["overwrite"][s] = false
        puts "#{s} disabled on #{n}"
      end
      role.save
    end
  end
end

class ServiceStartCmd < CmdParse::Command
  def initialize
    $parser.data[:all_services] = false
    super('start', takes_commands: false)
    short_desc('Start services from node')
  end

  def execute(node, *services)
    nodes = []
    utils = Utils.instance

    nodes = utils.check_nodes(node)
    if (nodes.count == 0)
      services.insert(0, node)
      nodes << Socket.gethostname.split(".").first 
    end

    nodes.each do |n|
      node = utils.get_node(n)

      unless node
        puts "ERROR: Node not found!"
        next
      end

      list_of_services = node.attributes['redborder']['services']

      services.each do |service|
        if list_of_services[service]
          ret = utils.remote_cmd(n, "systemctl start #{service} &>/dev/null") ? "started" : "failed to start"
          puts "#{service} #{ret} on #{n}"
        end
      end
    end
  end
end

class ServiceStopCmd < CmdParse::Command
  def initialize
    $parser.data[:all_services] = false
    super('stop', takes_commands: false)
    short_desc('Stop services from node')
  end

  def execute(node,*services)
    nodes = []
    utils = Utils.instance

    nodes = utils.check_nodes(node)
    if (nodes.count == 0)
      services.insert(0, node)
      nodes << Socket.gethostname.split(".").first 
    end

    nodes.each do |n|
      node = utils.get_node(n)

      unless node
        puts "ERROR: Node not found!"
        next
      end

      list_of_services = node.attributes['redborder']['services']

      services.each do |service|
        if list_of_services[service]
          ret = utils.remote_cmd(n, "systemctl stop #{service} &>/dev/null") ? "stopped" : "failed to stop"
          puts "#{service} #{ret} on #{n}"
        end
      end
    end
  end
end

$parser.add_command(ServiceCmd.new)
