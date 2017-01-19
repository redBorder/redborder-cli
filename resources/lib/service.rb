require 'chef'

class ServiceCmd < CmdParse::Command
  def initialize
    super('service')
    short_desc('Manage service actions and values')
    add_command(ServiceListCmd.new, default: true)
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
    services.each do |service,enabled|
      if $parser.data[:all_services] == false and enabled == false
        next
      else
        ret = system("systemctl status #{service} &>/dev/null") ? "OK" : "Fail"
        puts "Status of service #{service}: #{ret}"
      end
    end

  end
end

$parser.add_command(ServiceCmd.new)

