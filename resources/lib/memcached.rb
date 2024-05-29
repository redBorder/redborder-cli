require "dalli"
require 'net/telnet'
require 'yaml'
require "getopt/std"
require 'chef'

def logit(text)
  printf("%s\n", text)
end

def title
  logit "============================================================== Memcached ============================================================================"
end

def separator
  logit "-----------------------------------------------------------------------------------------------------------------------------------------------------"
end

def bottom
  logit "====================================================================================================================================================="
end

def subtitle(message)
  logit "----------------------------------------------------------------#{message}------------------------------------------------------------------------------"
end


class MemcachedCmd < CmdParse::Command
  def initialize
    super('memcached')
    short_desc('Memcached actions')
    add_command(MemcachedStatusCmd.new, default: true)
    add_command(MemcachedGetKeysCmd.new, default: false)
    add_command(MemcachedGetValueCmd.new, default: false)
  end
end

class MemcachedStatusCmd < CmdParse::Command
  def initialize
    super('status', takes_commands: false)
    short_desc('Shows status of memcached service')
    options.on('-s', '--stats')   { $parser.data[:stats]     = true  }
    options.on('-d', '--display') { $parser.data[:display]   = true }
    long_desc('Default option is "display".')
  end

  def execute()
    hosts = []
    utils = Utils.instance
    nodes = utils.get_consul_members

    nodes.each do |node|
      node_info = utils.get_node(node)
      
      unless node
        puts "ERROR: Node not found!"
        next
      end

      services = node_info.attributes['redborder']['services']
      hosts << node if services["memcached"]
    end

    if nodes.length > 0
      title
    end

    if ($parser.data[:stats] and $parser.data[:display])
      actions = ["display","stats"]
    elsif $parser.data[:stats]
      actions = ["stats"]
    else
      actions = ["display"]
    end
    actions.each do |action|
      subtitle(action)
      hosts.each do |host|
        subtitle(host)
        display_rows= `memcached-tool #{host}:11211 display | sed '1d'`.split("\n") if action == "display" #.gsub(/\s+/, " ")#.split("\n") if !$parser.data[:stats]
        stats_rows = `memcached-tool #{host}:11211 stats | sed '1d'`.split("\n") if action == "stats"#.split("\r")

        if action == "display"
          printf("%3s %16s %16s %16s %16s %16s %18s %18s %18s", "id", "Item_Size", "Max_age", "Pages", "Count", "Full?", "Evicted", "Evict_Time", "OOM" )
          printf("\n")

          display_rows.each do |row|
            row = row.gsub(/\s+/, " ").split
            printf("%3s %13s %19s %14s %17s %16s %16s %16s %22s", row[0], row[1], row[2], row[3], row[4], row[5], row[6], row[7], row[8])
            printf("\n")
          end

          separator

        else
          printf("%36s %68s", "Field", "Value")
          printf("\n")
          stats_rows.each do |row|
            row = row.split
            printf("%36s %68s", row[0], row[1])
            printf("\n")

            separator

          end

        end

        bottom
        printf("\n")

      end
    end
  end
end

class MemcachedGetKeysCmd < CmdParse::Command
  def initialize
    super('keys', takes_commands: false)
    short_desc('Shows memcached keys')
    long_desc('Patterns can be provided to filter memcached keys.')
    options.on('-v', '--invert-match') { $parser.data[:invert]   = true }
  end

  def execute(*pattern)
    # Credit to Graham King at http://www.darkcoding.net/software/memcached-list-all-keys/ for the original article on how to get the data from memcache in the first place.
    # Adapted by Pablo Nebrera (pablonebrera@eneotecnologia.com) --> rb_memcache_keys
    # Adapted by Eduardo Reyes (eareyes@redborder.com) --> rbcli command

    config = YAML.load_file('/var/www/rb-rails/config/memcached_config.yml')
    memcachservers=[config["production"]["servers"].sample]

    title

    memcachservers.each do |memhost|
      rows = []
      memhost_ip=memhost.split(':')[0]
      memhost_port=memhost.split(':')[1]
      memhost_port="11211" if memhost_port.nil?
      begin
        host = Net::Telnet::new("Host" => memhost_ip, "Port" => memhost_port.to_i, "Timeout" => 5)

        matches   = host.cmd("String" => "stats items", "Match" => /^END/).scan(/STAT items:(\d+):number (\d+)/)
        slabs = matches.inject([]) { |items, item| items << Hash[*['id','items'].zip(item).flatten]; items }


        slabs.each do |slab|
          begin
            host.cmd("String" => "stats cachedump #{slab['id']} #{slab['items']}", "Match" => /^END/) do |c|
              matches = c.scan(/^ITEM (.+?) \[(\d+) b; (\d+) s\]$/).each do |key_data|
                cache_key, bytes, expires_time = key_data
                rows << [slab['id'], Time.at(expires_time.to_i), bytes, cache_key]
              end
            end
          rescue StandardError => e
            puts e.message
          end
        end

        if rows.length > 0    #Print headers
          printf("%3s %15s %22s %45s", "id", "expires", "bytes", "key")
          printf("\n")
          separator
        end

        rows.each do |row|

          # invert-match option? #
          if $parser.data[:invert]
            next_row = false
          else
            next_row = true
          end
          #----------------------#

          # Is there any pattern? #
          if !pattern.empty?
            pattern.each do |p|
              if $parser.data[:invert]
                next_row = true if row[3].include? p
              else
                if row[3].include? p
                  next_row = false
                  break
                end
              end
            end
          end

          next if (next_row and !pattern.empty?) # Skip printing this key

          printf("%5s %25s %13s %45s", row[0] + " |", row[1].to_s + " | ", row[2] + " | ", row[3])
          printf("\n")
          separator if row!=rows.last

        end

        bottom

      rescue StandardError => e
        puts e.message
      ensure
        host.close unless host.nil?
      end
    end
  end
end


class MemcachedGetValueCmd < CmdParse::Command
  def initialize
    super('values', takes_commands: false)
    short_desc('Shows stored memcached values.')
    long_desc('Patterns can be provided to filter memcached keys.')
    options.on('-v', '--invert-match') { $parser.data[:invert]   = true }

  end

  def execute(*keys)

    keys = "#{keys.join("' '")}"

    if $parser.data[:invert]
      list_of_keys = `rbcli memcached keys -v '#{keys}' | awk -F"|" '{print $4}' | tr -d '\n'`.gsub(/\s+/, " ").split
    else
      list_of_keys = `rbcli memcached keys '#{keys}' | awk -F"|" '{print $4}' | tr -d '\n'`.gsub(/\s+/, " ").split
    end

    @memcached = Dalli::Client.new("memcached.service:11211", {:expires_in => 0})

    if list_of_keys.length > 0
      title
      printf("%15s %75s", "Key", "Value")
      printf("\n")
      separator

      list_of_keys.each do |k|
        value = @memcached.get("#{k}")
        printf("%-43s %50s", "#{k}", value.to_s)
        printf("\n")
        separator if k!=list_of_keys.last
      end
      bottom
    else
      puts "There is no entry in memcached for provided keys"
    end
  end
end

$parser.add_command(MemcachedCmd.new)

