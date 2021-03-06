#!/usr/bin/ruby
#-------------------------------------------------------------------------------
# Script to Save some Media notes into NotePlan
# by Jonathan Clark, v0.2.1, 5.2.2021
#-------------------------------------------------------------------------------
VERSION = "0.2.1"
require 'date'
require 'cgi'
require 'colorize'
require 'optparse' # more details at https://docs.ruby-lang.org/en/2.1.0/OptionParser.html

#-------------------------------------------------------------------------------
# Setting variables to tweak
#-------------------------------------------------------------------------------
NOTE_EXT = "md" # or "txt"
IFTTT_FILEPATH = "/Users/jonathan/Dropbox/IFTTT/"
IFTTT_ARCHIVE_FILEPATH = "/Users/jonathan/Dropbox/IFTTT/Archive/"
SPOTIFY_FILE = "Spotify Saved Tracks.txt"
INSTAPAPER_FILE = "Instapaper Archived Items.txt"
TWITTER_FILE = "My Tweets.txt"
YOUTUBE_LIKES_FILE = "YouTube liked videos.txt"
YOUTUBE_UPLOAD_FILE = "YouTube upload.txt"
DATE_TIME_LOG_FORMAT = '%e %b %Y %H:%M'.freeze # only used in logging
DATE_TIME_APPEND_FORMAT = '%Y%m%d%H%M'.freeze

#-------------------------------------------------------------------------------
# To use test data instead of live data, uncomment relevant definitions:
#-------------------------------------------------------------------------------
# $spotify_test_data = <<-END_S_DATA
# February 6, 2021 at 11:11PM | Espen Eriksen Trio | In the Mountains | Never Ending January | https://ift.tt/2TRqQiB | https://ift.tt/2LptJng
# February 6, 2021 at 11:56AM | Brian Doerksen | Creation Calls | Today | https://ift.tt/2qQI2Sq | https://ift.tt/3pYs1by
# END_S_DATA

# $instapaper_test_data = <<-END_I_DATA
# February 6, 2021 at 05:49AM \\ Thomas Creedy: Imago Dei \\ https://ift.tt/3rJl1Bh \\
# February 6, 2021 at 06:02AM \\ Is the 'seal of the confessional' Anglican? \\ https://ift.tt/2MpMAPX \\ "Andrew Atherstone writes: The Church of England has at last published the report of the 'Seal of the Confessional' working party , more than a year after it..."
# February 6, 2021 at 04:04PM \\ In what ways can we form useful relationships between notes? \\ https://ift.tt/3aT3LS3 \\ "Nick Milo Aug 8, 2020 * 7 min read Are you into personal knowledge management PKM)? Are you confused about when to use a folder versus a tag versus a link..."
# END_I_DATA

# $twitter_test_data = <<-END_T_DATA
# February 6, 2021 at 03:56PM | A useful thread which highlights the problems of asking the wrong question. https://t.co/xEKimf9cLK | jgctweets | http://twitter.com/jgctweets/status/1353371090609909760
# END_T_DATA

#-------------------------------------------------------------------------------
# Other Constants & Settings
#-------------------------------------------------------------------------------
USERNAME = ENV['LOGNAME'] # pull username from environment
USER_DIR = ENV['HOME'] # pull home directory from environment
DROPBOX_DIR = "#{USER_DIR}/Dropbox/Apps/NotePlan/Documents".freeze
ICLOUDDRIVE_DIR = "#{USER_DIR}/Library/Mobile Documents/iCloud~co~noteplan~NotePlan/Documents".freeze
CLOUDKIT_DIR = "#{USER_DIR}/Library/Containers/co.noteplan.NotePlan3/Data/Library/Application Support/co.noteplan.NotePlan3".freeze
# TodaysDate = Date.today # can't work out why this needs to be a 'constant' to work -- something about visibility, I suppose
np_base_dir = CLOUDKIT_DIR if Dir.exist?(CLOUDKIT_DIR) && Dir[File.join(CLOUDKIT_DIR, '**', '*')].count { |file| File.file?(file) } > 1
NP_CALENDAR_DIR = "#{np_base_dir}/Calendar".freeze

# Colours to use with the colorization gem
# to show some possible combinations, run  String.color_samples
# to show list of possible modes, run   puts String.modes  (e.g. underline, bold, blink)
String.disable_colorization false
CompletedColour = :light_green
InfoColour = :yellow
WarningColour = :light_red

# Variables that need to be globally available
time_now = Time.now
$date_time_now_log_fmttd = time_now.strftime(DATE_TIME_LOG_FORMAT)
$date_time_now_file_fmttd = time_now.strftime(DATE_TIME_APPEND_FORMAT)
$verbose = 0
$npfile_count = 0

#-------------------------------------------------------------------------
# Class definition: NPCalFile
#-------------------------------------------------------------------------
class NPCalFile
  # Define the attributes that need to be visible outside the class instances
  attr_reader :id, :media_header_line, :is_calendar, :is_updated, :filename, :line_count

  def initialize(date)
    # Create NPFile object from reading Calendar file of date YYYMMDD

    # Set the file's id
    $npfile_count += 1
    @id = $npfile_count
    @filename = "#{NP_CALENDAR_DIR}/#{date}.#{NOTE_EXT}"
    @lines = []
    @line_count = 0
    @media_header_line = 0
    @title = date
    @is_updated = false

    begin
      puts " Reading NPCalFile for '#{@title}'" if $verbose

      # initialise other variables (that don't need to persist with the class)
      n = 0

      # Open file and read in all lines (finding any Done and Cancelled headers)
      # NB: needs the encoding line when run from launchctl, otherwise you get US-ASCII invalid byte errors (basically the 'locale' settings are different)
      f = File.open(@filename, 'r', encoding: 'utf-8')
      f.each_line do |line|
        @lines[n] = line
        puts " #{n}: #{line}" if $verbose
        @media_header_line = n  if line =~ /^#+\s+Media/
        n += 1
      end
      f.close
      @line_count = @lines.size # e.g. for lines 0-2 size => 3
      puts " -> Read NPCalFile for '#{@title}' using id #{@id}. #{@line_count} lines (media at #{@media_header_line})" if $verbose
    rescue StandardError => e
      puts "ERROR: #{e.exception.message} when re-writing note file #{@filename}".colorize(WarningColour)
    end
  end

  def insert_new_line(new_line, line_number)
    # Insert 'line' into position 'line_number'
    # NB: this is insertion at the line number, so that current line gets moved to be one later
    n = @line_count # start iterating from the end of the array
    puts "  insert_new_line at #{line_number} (count=#{n}) ..." if $verbose
    # while n >= line_number
    #   @lines[n + 1] = @lines[n]
    #   n -= 1
    # end
    # @lines[line_number] = new_line
    @lines.insert(line_number, new_line)
    @line_count = @lines.size
  end

  def append_media_header
    # Add '### Media' on end, and update counts
    puts '  append_media_header ...' if $verbose
    insert_new_line('', @line_count)
    insert_new_line('### Media', @line_count)
    @media_header_line = @line_count
  end

  def rewrite_cal_file
    # write out this updated calendar file
    puts "  > writing updated version of #{@filename}".to_s.bold if $verbose
    # open file and write all the lines out
    begin
      File.open(@filename, 'w') do |f|
        @lines.each do |line|
          f.puts line
        end
      end
    rescue StandardError => e
      puts "ERROR: #{e.exception.message} when re-writing calendar file #{filepath}".colorize(WarningColour)
    end
  end
end

#--------------------------------------------------------------------------------------
# SPOTIFY
#--------------------------------------------------------------------------------------
def process_spotify
  spotify_filepath = IFTTT_FILEPATH + SPOTIFY_FILE
  catch (:done) do  # provide a clean way out of this
    if defined?($spotify_test_data)
      f = $spotify_test_data
      puts "Using Spotify test data"
    elsif File.exist?(spotify_filepath)
      if File.empty?(spotify_filepath)
        puts "Spotify file empty".colorize(InfoColour)
        throw :done
      else
        f = File.open(spotify_filepath, 'r', encoding: 'utf-8')
      end
    else
      puts "Spotify file not found".colorize(InfoColour)
      throw :done
    end

    begin
      f.each_line do |line|
        # Parse each line
        parts = line.split('|')
        puts parts if $verbose
        # parse the given date-time string, then create YYYYMMDD version of it
        date_YYYYMMDD = Date.parse(parts[0]).strftime('%Y%m%d')
        puts "  Found item to save with date #{date_YYYYMMDD}:" if $verbose

        # Format line to add
        line_to_add = "- new #spotify fave **#{parts[1].strip}**'s [#{parts[2].strip}](#{parts[4].strip}) from album **#{parts[3].strip}** ![album art](#{parts[5].strip})"
        puts line_to_add if $verbose

        # Read in the NP Calendar file for this date
        this_note = NPCalFile.new(date_YYYYMMDD)

        # Add new lines to end of file, creating a ### Media section before it if it doesn't exist
        this_note.append_media_header if this_note.media_header_line.zero?
        this_note.insert_new_line(line_to_add, this_note.line_count)
        this_note.rewrite_cal_file
        puts "-> Saved new Spotify fave to #{date_YYYYMMDD}".colorize(CompletedColour)
      end

      unless defined?($spotify_test_data)
        f.close
        # Now rename file to same as above but _YYYYMMDDHHMM on the end
        archive_filename = "#{IFTTT_ARCHIVE_FILEPATH}#{SPOTIFY_FILE[0..-5]}_#{$date_time_now_file_fmttd}.txt"
        File.rename(spotify_filepath, archive_filename)
      end
    rescue StandardError => e
      puts "ERROR: #{e.exception.message} for file #{SPOTIFY_FILE}".colorize(WarningColour)
    end
  end
end

#--------------------------------------------------------------------------------------
# INSTAPAPER
#--------------------------------------------------------------------------------------
def process_instapaper
  instapaper_filepath = IFTTT_FILEPATH + INSTAPAPER_FILE
  catch (:done) do  # provide a clean way out of this
    if defined?($instapaper_test_data)
      f = $instapaper_test_data
      puts "Using Instapaper test data"
    elsif File.exist?(instapaper_filepath)
      if File.empty?(instapaper_filepath)
        puts "Note: Instapaper file empty".colorize(InfoColour)
        throw :done
      else
        f = File.open(instapaper_filepath, 'r', encoding: 'utf-8')
      end
    else
      puts "Instapaper file not found".colorize(InfoColour)
      throw :done
    end

    begin
      f.each_line do |line|
        # Parse each line
        parts = line.split(" \\ ")
        # puts "  #{line} --> #{parts}" if $verbose
        # parse the given date-time string, then create YYYYMMDD version of it
        date_YYYYMMDD = Date.parse(parts[0]).strftime('%Y%m%d')
        puts "  Found item to save with date #{date_YYYYMMDD}:" if $verbose

        # Format line to add. Guard against possible empty fields
        parts[2] = '' if parts[2].nil?
        parts[3] = '' if parts[3].nil?
        line_to_add = "- #article **[#{parts[1].strip}](#{parts[2].strip})** #{parts[3].strip}"
        puts line_to_add if $verbose

        # Read in the NP Calendar file for this date
        this_note = NPCalFile.new(date_YYYYMMDD)

        # Add new lines to end of file, creating a ### Media section before it if it doesn't exist
        this_note.append_media_header if this_note.media_header_line.zero?
        this_note.insert_new_line(line_to_add, this_note.line_count)
        this_note.rewrite_cal_file
        puts "-> Saved new Instapaper item to #{date_YYYYMMDD}".colorize(CompletedColour)
      end

      unless defined?($instapaper_test_data)
        f.close
        # Now rename file to same as above but _YYYYMMDDHHMM on the end
        archive_filename = "#{IFTTT_ARCHIVE_FILEPATH}#{INSTAPAPER_FILE[0..-5]}_#{$date_time_now_file_fmttd}.txt"
        File.rename(instapaper_filepath, archive_filename)
      end
    rescue StandardError => e
      puts "ERROR: #{e.exception.message} when processing file #{INSTAPAPER_FILE}".colorize(WarningColour)
    end
  end
end

#--------------------------------------------------------------------------------------
# TWITTER
#--------------------------------------------------------------------------------------
def process_twitter
  twitter_filepath = IFTTT_FILEPATH + TWITTER_FILE
  catch (:done) do  # provide a clean way out of this
    if defined?($twitter_test_data)
      f = $twitter_test_data
      puts "Using Twitter test data"
    elsif File.exist?(twitter_filepath)
      if File.empty?(twitter_filepath)
        puts "Note: Twitter file empty".colorize(InfoColour)
        throw :done
      else
        f = File.open(twitter_filepath, 'r', encoding: 'utf-8')
      end
    else
      puts "Twitter file not found".colorize(InfoColour)
      throw :done
    end

    begin
      f.each_line do |line|
        # Parse each line
        parts = line.split(" | ")
        # puts "  #{line} --> #{parts}" if $verbose
        # parse the given date-time string, then create YYYYMMDD version of it
        date_YYYYMMDD = Date.parse(parts[0]).strftime('%Y%m%d')
        puts "  Found item to save with date #{date_YYYYMMDD}:" if $verbose

        # Format line to add
        line_to_add = "- @#{parts[2].strip} tweet: \"#{parts[1].strip}\" ([permalink](#{parts[3].strip}))"
        puts line_to_add if $verbose

        # Read in the NP Calendar file for this date
        this_note = NPCalFile.new(date_YYYYMMDD)

        # Add new lines to end of file, creating a ### Media section before it if it doesn't exist
        this_note.append_media_header if this_note.media_header_line.zero?
        this_note.insert_new_line(line_to_add, this_note.line_count)
        this_note.rewrite_cal_file
        puts "-> Saved new Twitter item to #{date_YYYYMMDD}".colorize(CompletedColour)
      end

      unless defined?($twitter_test_data)
        f.close
        # Now rename file to same as above but _YYYYMMDDHHMM on the end
        archive_filename = "#{IFTTT_ARCHIVE_FILEPATH}#{TWITTER_FILE[0..-5]}_#{$date_time_now_file_fmttd}.txt"
        File.rename(twitter_filepath, archive_filename)
      end
    rescue StandardError => e
      puts "ERROR: #{e.exception.message} when processing file #{TWITTER_FILE}".colorize(WarningColour)
    end
  end
end

#=======================================================================================
# Main logic
#=======================================================================================

# Setup program options
options = {}
opt_parser = OptionParser.new do |opts|
  opts.banner = "NotePlan media adder v#{VERSION}" # \nDetails at https://github.com/jgclark/NotePlan-tools/\nUsage: npMediaSave.rb [options]"
  opts.separator ''
  options[:instapaper] = false
  options[:spotify] = false
  options[:twitter] = false
  options[:verbose] = false
  opts.on('-h', '--help', 'Show this help') do
    puts opts
    exit
  end
  opts.on('-i', '--instapaper', 'Add Instapaper records') do
    options[:instapaper] = true
  end
  opts.on('-s', '--spotify', 'Add Spotify records') do
    options[:spotify] = true
  end
  opts.on('-t', '--twitter', 'Add Twitter records') do
    options[:twitter] = true
  end
  opts.on('-v', '--verbose', 'Show information as I work [on by default at the moment]') do
    options[:verbose] = true
  end
end
opt_parser.parse! # parse out options, leaving file patterns to process

puts "Starting npSaveMedia at #{$date_time_now_log_fmttd}."
process_instapaper if options[:instapaper]
process_spotify if options[:spotify]
process_twitter if options[:twitter]
