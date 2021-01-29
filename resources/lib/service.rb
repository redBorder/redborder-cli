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
    services.each do |service,enabled|
      if $parser.data[:all_services] == false and enabled == false
        next
      else
        systemd_services[service].each do |systemd_service|
          ret = system("systemctl status #{systemd_service} &>/dev/null") ? "OK" : "Fail"
          puts "Status of service #{systemd_service}: #{ret}"
        end
      end
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
    if services.include? service
      role = Chef::Role.load(Socket.gethostname.split(".").first)
      if !role.override_attributes["redborder"]["services"][service] or (role.override_attributes["redborder"]["services"][service] and role.override_attributes["redborder"]["services"][service] == false)
        role.override_attributes["redborder"]["services"][service] = true
        role.save
      else
        puts "The service #{service} was already enabled."
      end
     else
       puts "The service #{service} doesn't exists."
     end
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
      if services.include? service
      role = Chef::Role.load(Socket.gethostname.split(".").first)
      if role.override_attributes["redborder"]["services"][service]
        role.override_attributes["redborder"]["services"].delete(service)
        role.save
      else
        puts "The service #{service} was already disabled."
      end
     else
       puts "The service #{service} doesn't exists."
     end

  end
end
$parser.add_command(ServiceCmd.new)

