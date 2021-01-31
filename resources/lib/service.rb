require 'chef'

class ServiceCmd < CmdParse::Command
  def initialize
    super('service')
    short_desc('Manage service actions and values')
    add_command(ServiceListCmd.new, default: true)
    add_command(ServiceEnableCmd.new, default: true)
    add_command(ServiceDisableCmd.new, default: true)
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

    Chef::Config.from_file("/etc/chef/client.rb")
    Chef::Config[:client_key] = "/etc/chef/client.pem"
    Chef::Config[:http_retry_count] = 5

    node = Chef::Node.load(Socket.gethostname.split(".").first)
    services = node.attributes.redborder.services
    systemd_services = node.attributes.redborder.systemdservices
    systemctl_services = []
    services.each do |service,enabled|
      if $parser.data[:all_services] == false and enabled == false
        next
      else
        systemd_services[service].each do |systemd_service|
          systemctl_services.push(systemd_service)
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

  def execute(service,*opt)

    Chef::Config.from_file("/etc/chef/client.rb")
    Chef::Config[:client_key] = "/etc/chef/client.pem"
    Chef::Config[:http_retry_count] = 5

    node = Chef::Node.load(Socket.gethostname.split(".").first)
    services = node.attributes.redborder.services
    systemd_services = node.attributes.redborder.systemdservices
    
    group_of_the_service = systemd_services[service]
    services_with_same_group = systemd_services.select{|service,group| group == group_of_the_service }.keys || []

    role = Chef::Role.load(Socket.gethostname.split(".").first)
    role.override_attributes["redborder"]["services"] = {} if !role.override_attributes["redborder"].include? "services" # Initialize services in case do not exists
   
    services_with_same_group = [service] if services_with_same_group.empty? and services.include? service # in case is the service is not definde in systemdservices

    services_with_same_group.each do |s|
       role.override_attributes["redborder"]["services"][s] = true
       puts "#{s} enabled."
    end
    role.save

  end
end

class ServiceDisableCmd < CmdParse::Command
  def initialize
    $parser.data[:all_services] = false
    super('disable', takes_commands: false)
    short_desc('Disable service from node')
  end

  def execute(service,*opt)

    Chef::Config.from_file("/etc/chef/client.rb")
    Chef::Config[:client_key] = "/etc/chef/client.pem"
    Chef::Config[:http_retry_count] = 5

    node = Chef::Node.load(Socket.gethostname.split(".").first)
    services = node.attributes.redborder.services
    systemd_services = node.attributes.redborder.systemdservices

    group_of_the_service = systemd_services[service]
    services_with_same_group = systemd_services.select{|service,group| group == group_of_the_service }.keys || []

    role = Chef::Role.load(Socket.gethostname.split(".").first)
    role.override_attributes["redborder"]["services"] = {} if !role.override_attributes["redborder"].include? "services" # Initialize services in case do not exists

    services_with_same_group = [service] if services_with_same_group.empty? and services.include? service # in case is the service is not definde in systemdservices

    services_with_same_group.each do |s|
       role.override_attributes["redborder"]["services"][s] = false
       puts "#{s} disabled."
    end
    role.save

  end
end
$parser.add_command(ServiceCmd.new)

