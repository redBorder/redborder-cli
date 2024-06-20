#!/usr/bin/env ruby

require 'cmdparse'

$parser = CmdParse::CommandParser.new(handle_exceptions: :no_help)

Dir["#{ENV['RBLIB']}/rbcli/*.rb"].each { |file| require file }

$parser.global_options do |opt|
	opt.on("-V","--verbose","Enable verbosity") do
		$parser.data[:verbose] = true
	end
end

$parser.main_options.program_name = "rbcli"
$parser.main_options.version = "1.0.2"
$parser.main_options.banner = "This is the redborder CLI program"

#$parser.main_options do |opt|
#	opt.on("-v","--version","Show version") do
#		puts "redborder CLI 0.0.1"
#	end
#end

$parser.add_command(CmdParse::HelpCommand.new, default: true)
$parser.add_command(CmdParse::VersionCommand.new)

$parser.parse

