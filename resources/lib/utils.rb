require 'singleton'
require 'net/http'
require 'uri'
require 'json'
require 'chef'
require 'pathname'

class Utils
   include Singleton

  def initialize

  end

  def remote_cmd(node, *cmd)
    ret = system("ssh -o ConnectTimeout=5 -o LogLevel=quiet -o UserKnownHostsFile=/dev/null -o PasswordAuthentication=no -o StrictHostKeyChecking=no -i /var/www/rb-rails/config/rsa root@#{node} " + cmd.join(' '))
  end

  def remote_copy(node, path)
    target = Pathname.new(path).parent.to_s
    ret = system("scp -r -i /var/www/rb-rails/config/rsa -o StrictHostKeyChecking=no -o PasswordAuthentication=no #{path} root@#{node}:#{target}")
  end

  def get_consul_members
    nodes = []
    uri = URI.parse("http://localhost:8500/v1/agent/members")
    response = Net::HTTP.get_response(uri)
    if response.code == "200"
      ret = JSON.parse(response.body)
      ret.map { |member| nodes << member["Name"]}
      return nodes
    else
      []
    end
  end

  # get node information from chef
  def get_node(node_name)
    Chef::Config.from_file("/etc/chef/client.rb")
    Chef::Config[:client_key] = "/etc/chef/client.pem"
    Chef::Config[:http_retry_count] = 5
    node = Chef::Node.load(node_name)
  end

  # check if the parameter node is in the list of nodes
  def check_nodes(node)
    nodes = []
    all_nodes = get_consul_members
    if (node.downcase != "all")
      nodes << node if all_nodes.include? node
    else
      nodes = all_nodes
    end
    return nodes
  end


  # Logstash Utils
  def get_logstash_pipelines
    logstash_api_query('_node/stats/pipelines')
  end

  def get_logstash_pipeline(pipeline)
    logstash_api_query('_node/stats/pipelines/' + pipeline)
  end


  def get_logstash_status
    logstash_api_query('_node/stats/process')
  end

  def get_logstash_plugins
    logstash_api_query('_node/plugins')
  end

  #  curl -XGET 'localhost:9600/_node/stats/pipelines/vault-pipeline'

  def logstash_api_query(action)
   uri = URI.parse("http://localhost:9600/#{action}")
   response = Net::HTTP.get_response(uri) rescue {}
   unless response.class == Hash
     if !response.body.empty? and response.code == "200"
       JSON.parse(response.body) rescue {}
     else
       {}
     end
   else
     {}
   end
  end
end

