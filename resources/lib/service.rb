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
  def initialize
    $parser.data[:all_services] = false
    super('list', takes_commands: false)
    short_desc('List services from node')
    options.on('-x', '--extend', 'Extended information') { puts 'Extended information' }
    options.on('-a', '--all', 'All services') { $parser.data[:all_services] = true }
  end

  def execute()
    utils = Utils.instance
    node = utils.get_node(Socket.gethostname.split(".").first)
    
    services = node.attributes.redborder.services
    systemd_services = node.attributes.redborder.systemdservices
    systemctl_services = []
    services.each do |service,enabled|
      if $parser.data[:all_services] == false and enabled == false
        next
      else
        if systemd_services and systemd_services[service] 
          systemd_services[service].each do |systemd_service|
            systemctl_services.push(systemd_service)
          end
        end
      end
    end

    systemctl_services.uniq.each do |systemd_service|
          ret = system("systemctl status #{systemd_service} &>/dev/null") ? "OK" : "Fail"
          puts "Status of service #{systemd_service}: #{ret}"
    end

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
      services = node.attributes.redborder.services
      systemd_services = node.attributes.redborder.systemdservices
    
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
      services = node.attributes.redborder.services
      systemd_services = node.attributes.redborder.systemdservices

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
      list_of_services = node.attributes.redborder.services

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
      list_of_services = node.attributes.redborder.services

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

