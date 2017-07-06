#!/usr/bin/env ruby

require 'optparse'

require 'exif' # fast exif for images
require 'mini_exiftool' # slow, cmd exiftool wrapper, supports movies

require 'tty-prompt'
require 'pastel'
require 'fileutils'

pastel = Pastel.new(enabled: $stdout.tty?, eachline: "\n")
verbose  = pastel.yellow.detach

prompt = TTY::Prompt.new

options = {
  verbose: false,
  dry_run: false,
  enforce_gps: false,
  move: false
}
OptionParser.new do |opt|
  opt.banner = "Usage: organize.rb [options] src dst"

  opt.on('-v', '--[no-]verbose', 'Run verbosely') { |v| options[:verbose] = v }
  opt.on('--dry-run', 'Run whole program but do not actually perform any changes to files. Implies --verbose.') do
    options[:dry_run] = true
    options[:verbose] = true
  end
  opt.on('--[no-]enforce-gps', 'Abort if any photo misses GPS data') { |v| options[:enforce_gps] = v }
  opt.on_tail('-h', '--help', 'Prints help') { puts opt.help(); exit }
end.parse!

if ARGV.size != 2
  prompt.error("Wrong number of arguments, expected 2 (src and dst), got #{ARGV.size}: #{ARGV.join(' ')}")
  exit 1
end
src = ARGV[0]
dst = ARGV[1]

unless Dir.exist?(src)
  prompt.error("#{src} is not a directory")
  exit 1
end
unless Dir.exist?(dst)
  if File.exist?(dst)
    prompt.error("#{dst} is not a directory. Aborting")
    exit 1
  elsif prompt.yes?("#{dst} does not exist. Create it?")
    FileUtils.mkpath(dst, noop: options[:dry_run], verbose: options[:verbose])
  else
    prompt.error("#{dst} does not exist. Aborting")
    exit 1
  end
end


class Image
  attr_reader :filename, :exif

  def initialize(filename)
    @filename = filename
    @exif = Exif::Data.new(filename)
  end

  def has_gps?
    !@exif[:gps_latitude].nil?
  end

  def date_time
    @exif[:date_time_original]&.getutc
  end

  def ext
    '.jpg'
  end
end

class Movie
  attr_reader :filename, :exif

  def initialize(filename)
    @filename = filename
    @exif = MiniExiftool.new filename
  end

  def has_gps?
    true # don't care about geolocation in movies cause I lack tools to add them manually
  end

  def date_time
    @exif.creation_date || @exif.media_create_date || @exif.file_modify_date || File::Stat.new(filename).mtime
  end

  def ext
    '.mov'
  end
end

def walk(start)
  result = Array.new
  walk_recursive = lambda do |start, acc|
    Dir.foreach(start) do |uri|
      path = File.join(start, uri)
      if %w(. ..).include?(uri)
        next
      elsif File.directory?(path)
        walk_recursive.call(path, acc)
      else
        acc << path
      end
    end
  end
  walk_recursive.call(start, result)
  result
end

files = walk(src)

movies = files
  .select { |filename| /mov$/i === filename }
  .map { |filename| Movie.new(filename) }

photos = files
  .select { |filename| /jpe?g$/i === filename }
  .map { |filename| Image.new(filename) }

photos_without_gps = photos.select { |photo| !photo.has_gps? }

unless photos_without_gps.empty?
  pluralized_images = photos_without_gps.size == 1 ? "1 photo is" : "#{photos_without_gps.size} photos are"
  prompt.warn("#{pluralized_images} missing gps data")
  photos_without_gps.each { |img| prompt.warn(img.filename) } if options[:verbose]
  if options[:enforce_gps]
    prompt.error('Aborting')
    exit
  elsif options[:enforce_gps].nil? && prompt.no?('Do you want to continue?')
    prompt.error('Aborting')
    exit
  end
end

files = photos + movies
files.group_by { |any_image| any_image.date_time.year }.each do |year, yearly|
  output_year = File.join(dst, year.to_s)
  FileUtils.mkdir(output_year, noop: options[:dry_run], verbose: options[:verbose]) unless Dir.exist?(output_year)
  yearly.each do |image|
    datetime = image.date_time.strftime("%Y-%m-%d %H-%M-%S")
    idx = 1
    output_filename = datetime + image.ext
    while File.exist?(File.join(output_year, output_filename))
      output_filename = [datetime, " (#{idx})", image.ext].join
      idx += 1
    end
    FileUtils.cp(image.filename, File.join(output_year, output_filename), noop: options[:dry_run], verbose: options[:verbose])
  end
end
