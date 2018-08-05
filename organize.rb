#!/usr/bin/env ruby

require "exif" # fast exif for images
require "mini_exiftool" # slow, cmd exiftool wrapper, supports movies

require "fileutils"
require "find"
require "optparse"
require "pastel"
require "shellwords"
require "tty-prompt"

pastel = Pastel.new(enabled: $stdout.tty?, eachline: "\n")

prompt = TTY::Prompt.new

options = {
  verbose: false,
  dry_run: false,
  enforce_gps: true,
}
OptionParser.new do |opt|
  opt.banner = "Usage: organize.rb [options] src dst"

  opt.on("-v", "--[no-]verbose", "Run verbosely") { |v| options[:verbose] = v }
  opt.on("--dry-run", "Run whole program but do not actually perform any changes to files. Implies --verbose.") do
    options[:dry_run] = true
    options[:verbose] = true
  end
  opt.on("--[no-]enforce-gps", "Abort if any photo misses GPS data") { |v| options[:enforce_gps] = v }
  opt.on_tail("-h", "--help", "Prints help") { puts opt.help(); exit }
end.parse!

if ARGV.size != 2
  prompt.error("Wrong number of arguments, expected 2 (src and dst), got #{ARGV.size}: #{ARGV.join(" ")}")
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

class Media
  attr_reader :filename

  def extname
    File.extname(@filename).downcase
  end
end

class Image < Media
  def self.===(path)
    /jpe?g$/i === path
  end

  def initialize(filename)
    @filename = filename
    @exif = Exif::Data.new(File.open(filename))
  end

  def has_gps?
    !@exif[:gps].empty?
  end

  def create_time
    Time.strptime(@exif.date_time_original, "%Y:%m:%d %H:%M:%S").getutc
  end
end

class Movie < Media
  def self.===(path)
    /(mov|mp4)$/i === path
  end

  def initialize(filename)
    @filename = filename
    @exif = MiniExiftool.new filename
  end

  def has_gps?
    true # don't care about geolocation in movies cause I lack tools to add them manually
  end

  def create_time
    (@exif[:date_time_original] ||
     @exif[:create_date] ||
     @exif[:media_create_date] ||
     @exif[:file_modify_date]).getutc
  end
end

def is_media?(path)
  [Movie, Image].any? { |c| c === path }
end

def create_media(path)
  case path
  when Image
    Image.new(path)
  when Movie
    Movie.new(path)
  end
end

files = Find.find(src)
  .select { |path| File.file?(path) }
  .select { |path| is_media?(path) }
  .map { |path| create_media(path) }

files_without_gps = files.select { |f| !f.has_gps? }

unless files_without_gps.empty?
  pluralized_images = files_without_gps.size == 1 ? "1 photo is" : "#{files_without_gps.size} photos are"
  prompt.warn("#{pluralized_images} missing gps data")
  files_without_gps.each { |img| prompt.warn(img.filename) } if options[:verbose]
  if options[:enforce_gps]
    prompt.error("Aborting")
    exit
  elsif prompt.no?("Do you want to continue?")
    prompt.error("Aborting")
    exit
  end
end

def fast_system_copy(src, dst, noop, verbose)
  puts "Copying #{src.shellescape} -> #{dst.shellescape}" if verbose
  `cp -pc #{src.shellescape} #{dst.shellescape}` unless noop
end

files.group_by { |media| media.create_time.year }.each do |year, yearly|
  output_year = File.join(dst, year.to_s)
  FileUtils.mkdir(output_year, noop: options[:dry_run], verbose: options[:verbose]) unless Dir.exist?(output_year)
  yearly.each do |image|
    datetime = image.create_time.strftime("%Y-%m-%d %H-%M-%S")
    idx = 1
    output_filename = datetime + image.extname
    while File.exist?(File.join(output_year, output_filename))
      output_filename = [datetime, " (#{idx})", image.ext].join
      idx += 1
    end
    fast_system_copy(image.filename, File.join(output_year, output_filename), options[:dry_run], options[:verbose])
  end
end
