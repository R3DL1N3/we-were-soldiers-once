dir, _ = File.split __FILE__
dcs_dir = File.join ENV['HOME'], 'Saved Games', 'DCS.openalpha'
miz_dir = File.join dcs_dir, 'Missions'
miz_path = File.join miz_dir, File.basename(dir) + '.miz'

$: << File.join(dcs_dir, 'World', 'lib')

require 'miz'

task :zip do |task|
  Zip::File.open miz_path, true do |miz|
    %w[mission warehouses options].each do |name|
      miz.get_output_stream name do |file|
        file.write File.open(File.join(dir, name), 'rb').read
      end
    end
    Dir[File.join dir, 'l10n', '**', '*'].each do |path|
      next unless File.file? path
      name = Pathname.new(path).relative_path_from Pathname.new(dir)
      miz.get_output_stream name.to_path do |file|
        file.write File.open(path, 'rb').read
      end
    end
  end
end

task :fix do |task|
  miz = Miz.new miz_path

  # Resolve the mission dictionary keys and export the mission to YAML.
  File.open File.basename(miz_path, '.*') + '.yml', 'w' do |file|
    file.write miz.mission_dup_resolve_sort.to_yaml
  end

  miz.clean_dict_keys
  miz.fix
  miz.commit
end

task :unzip do |task|
  miz = Miz.new miz_path
  miz.entries.each do |entry|
    entry_path = File.join dir, entry.name
    FileUtils.mkdir_p File.dirname(entry_path)
    entry.extract(entry_path) { true }
  end
end
