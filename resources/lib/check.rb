require "getopt/std"
require 'chef'
require_relative "/usr/lib/redborder/lib/check_functions.rb"

USAGE = <<ENDUSAGE

Usage: check [-h] [-s <service_name>] [-o <output_file>] [-u <s3path>] [-k <X>] [-c] [-q] [-e]

ENDUSAGE

HELP = <<ENDHELP
   service <service_name>      Show only information about this service name.
   output_file <output_file>   Stdout to this file instead of stdout.
   upload <s3path>             Upload output to this s3 path.
   keep <X>                    Keep last X files into s3.
   colorless                   Do not use colors.
   extended                    Show extended cluster information.
   quiet                       Be quiet.

ENDHELP

ARGS = { :colorless => false, :extended=> false, :quiet=> false, :service => nil}   # Setting default values
UNFLAGGED_ARGS = [ :directory ]     # Bare arguments (no flag)


class CheckCmd < CmdParse::Command
  def initialize
    super('check')
    short_desc('Check all cluster nodes status')
    add_command(CheckStatusCmd.new, default: true)
    add_command(CheckHelpCmd.new)
  end
end

class CheckHelpCmd < CmdParse::Command
  def initialize
    super('help', takes_commands: false)
  end

  def execute( )
    puts USAGE
    puts HELP
  end
end

class CheckStatusCmd < CmdParse::Command
  def initialize
    super('status', takes_commands: false)
  end

  def execute( *argv )
    next_arg = UNFLAGGED_ARGS.first
    argv.each do |arg|
      case arg
      when 'service'       then next_arg           = :service
      when 'output_file'   then next_arg           = :output_file
      when 'upload'        then next_arg           = :upload
      when 'keep'          then next_arg           = :keep
      when 'colorless'     then ARGS[:colorless]   = true
      when 'extended'      then ARGS[:extended]    = true
      when 'quiet'         then ARGS[:quiet]       = true
      else
        if next_arg
          ARGS[next_arg] = arg
          UNFLAGGED_ARGS.delete( next_arg )
        end
        next_arg = UNFLAGGED_ARGS.first
      end
    end

    colorless = ARGS[:colorless]
    quiet = ARGS[:quiet]
    service = ARGS[:service]
    time = Time.utc(*Time.new.to_a).to_s

    commons = %w[hd install io killed licenses memory]
    check_dir = "/usr/lib/redborder/lib/check"
    title_ok("DATE:  " + time,colorless,quiet)

    if service.nil?
      directories = Dir.entries(check_dir).select{
        |entry| File.directory? File.join(check_dir,entry) and
          !(entry =='.' || entry == '..' || entry == 'commons') }
      puts directories
    else

    end
  end
end
$parser.add_command(CheckCmd.new)
