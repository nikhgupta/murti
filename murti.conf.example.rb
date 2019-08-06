sp = "(?:|\.|-|_)"
raw2jpg = Proc.new do
  co = `which convert 2>/dev/null`.strip
  et = `which exiftool 2>/dev/null`.strip
  jpg_path = File.join(File.dirname(path), "#{File.basename(path, '.*')}.jpg")

  if !File.exist?(jpg_path) && !co.empty? && !et.empty?
    command = []
    command << "#{co} \"#{path}\" \"#{jpg_path}\" 2>/dev/null"
    command << "#{et} -TagsFromFile \"#{path}\" \"#{jpg_path}\" 2>/dev/null"
    command << "rm -f \"#{jpg_path}_original\" 2>/dev/null"
    success = system(command.join(" && "))
    puts "[FAIL]: #{path} => PROCESSING RAW2JPG" unless success
    add_file_for_migration jpg_path if File.exist?(jpg_path)
  end
end

Murti.configure do
  group do
    # Directories to extract files from on each run.
    source_directory "/media/Data/DUMP"
    source_directory "/media/Data/UNMATCHED"
    source_directory "/media/Data/Videos", on: :refresh
    source_directory "/media/Data/Pictures", on: :refresh
    source_directory "/media/Data/Live Photos", on: :refresh

    # directory where files would be renamed/moved/copied to.
    target_directory "/media/Data"
  end

  group :external do
    # Directories to extract files from on each run.
    source_directory "/run/media/nikhgupta/PICTURES/DUMP"
    source_directory "/run/media/nikhgupta/PICTURES/UNMATCHED"
    source_directory "/run/media/nikhgupta/PICTURES/Videos", on: :refresh
    source_directory "/run/media/nikhgupta/PICTURES/Pictures", on: :refresh
    source_directory "/run/media/nikhgupta/PICTURES/Live Photos", on: :refresh

    # directory where files would be renamed/moved/copied to.
    target_directory "/run/media/nikhgupta/PICTURES"
  end

  # what kind of strategy we are using here?
  # can be either :test, :move or :copy
  use_strategy :test

  # folder structure, e.g. "2019/2019-06-19"
  set_date_format "%Y/%Y-%m-%d"

  # skip hidden files
  skip_if :hidden
  # skip_if extension: [/\A\z/, :pdf, :exe, :zip, :tar, :lrprev, /\Adocx?\z/]
  skip_if extension_not_in: [/jpe?g/, :mp4, :mov, :ai, :psd, :png, :bmp, :gif, :avi, :cr2, :webp, :tiff, :raw, :eps, :svg, :aae, :dng, :xmp]
  skip_if path: /\/\.cache\/\.temp\//
  skip_if path: /\/\.cache\/.*\/[a-f0-9]{32}\.[^\/]+\z/
  skip_if path: /\/\.thumbnails?\//

  extract :timestamp, exif: :occurrence

  extract :timestamp, name: /\A(\d{19})\..*\z/ do |m|
    Time.at(m[0].to_f/1e9)
  end

  extract :timestamp, name: /\A(\d{13})\..*\z/ do |m|
    Time.at(m[0].to_f/1e3)
  end

  extract :timestamp, name: /(\d{4})#{sp}(\d{2})#{sp}(\d{2})#{sp}(\d{2})#{sp}(\d{2})#{sp}(\d{2})#{sp}(\d+)/ do |m|
    "#{m[0]}/#{m[1]}/#{m[2]} #{m[3]}:#{m[4]}:#{m[5]}.#{m[6]}"
  end

  extract :timestamp, name: /(\d{4})#{sp}(\d{2})#{sp}(\d{2})#{sp}(\d{2})#{sp}(\d{2})#{sp}(\d{2})/ do |m|
    "#{m[0]}/#{m[1]}/#{m[2]} #{m[3]}:#{m[4]}:#{m[5]}"
  end

  # whatsapp images and videos
  extract :timestamp, name: /\A(?:IMG|VID)#{sp}(\d{4})(\d{2})(\d{2})#{sp}WA\d+/i do |m|
    "#{m[0]}/#{m[1]}/#{m[2]}"
  end

  extract :timestamp, name: /\A(?:IMG|VID)#{sp}(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})\./ do |m|
    "#{m[0]}/#{m[1]}/#{m[2]} #{m[3]}:#{m[4]}:#{m[5]}"
  end

  extract :timestamp, path: /\/Google\/(\d{4})-(\d{2})-(\d{2})(?:| \#\d+|-\d+| - \d+-\d+)\// do |m|
    "#{m[0]}/#{m[1]}/#{m[2]}"
  end

  extract :timestamp, path: /\/\d{4}\/(\d{4})-(\d{2})-(\d{2})\// do |m|
    "#{m[0]}/#{m[1]}/#{m[2]}"
  end

  extract :timestamp, path: /dt\.\s*(\d{2})(\d{2})(\d{4})(?:\/|\.[^\/]+)/ do |m|
    "#{m[2]}/#{m[1]}/#{m[0]}"
  end

  extract :timestamp, name: /\A(\d{2})-(\d{2})-(\d{4})(?:_| )/ do |m|
    "#{m[2]}/#{m[1]}/#{m[0]}"
  end

  # try extracting date from file data
  # extract_timestamp_from_file_data strategy: :oldest

  rule name_regex: /\A\d{4}\d*_\d{10}\d*_\d{5}\d*_(?:n|o)(?:|_\d+)\./ do
    save_in "Pictures/Facebook"
  end

  rule :valid_date, name_regex: /\AIMG_\d+(?:|-\d+)\.MOV\z/i do
    size = File.stat(path).size/1024.0/1024.0
    save_in(size > 10 ? "Videos/%{date_format}" : "Live Photos/%{date_format}")
  end

  rule :valid_date, extension: [:mp4, :mov, :avi] do
    save_in "Videos/%{date_format}"
  end

  rule :valid_date, extension: [:cr2] do
    migrate(&raw2jpg)
    save_in "Pictures/RAW/%{date_format}"
  end

  rule :valid_date, extension: [/jpe?g/, :png, :webp, :gif, :bmp, :tiff] do
    save_in "Pictures/%{date_format}"
  end

  rule :valid_date do
    save_in "UNKNOWN/%{date_format}"
  end

  # Rule: Apple Live Photo Videos
  rule name_regex: /\AIMG_\d+(?:|-\d+)\.MOV\z/i do
    size = File.stat(path).size/1024.0/1024.0
    save_in(size > 10 ? "Videos" : "Live Photos")
  end

  rule extension: [:webp] do
    save_in "Pictures/webp"
  end

  rule extension: [:dng, :xmp, :aae] do
    FileUtils.rm path
  end

  rule extension: [:mp4, :mov, :avi] do
    save_in "Videos/DUMP"
  end

  rule extension: [:cr2] do
    migrate(&raw2jpg)
    save_in "RAW/DUMP"
  end

  rule extension: [/jpe?g/, :png, :webp, :gif, :bmp, :tiff] do
    save_in "Pictures/DUMP"
  end

  # Rule: If we have a file that does not match any
  # of the above rules, place it inside `unmatched` directory.
  rule :is_unmatched do
    save_in "UNMATCHED/%{path_component}"
  end

  # Rule: if we have a file that is identical to an
  # existing image file (destination path and hash),
  # we will delete that file.
  rule :is_duplicate do
    # FileUtils.unlink(path)
    save_prefix duplicate_number > 0 ? "DUPLICATE-#{duplicate_number}" : "DUPLICATE"
  end
end
