require 'rfusefs'
require 'json'
require 'uri'
require 'yaml'
require 'hashdiff'

tracker_token = ENV.fetch('TRACKER_TOKEN')
project = ENV.fetch('PROJECT_ID')

class Stories
  def initialize
    @stories = []
  end

  def path_id(path)
    /(\d+)\.story$/.match(path)[1].to_i
  end

  def contents(path)
    stories = JSON.load(`curl -X GET -H "X-TrackerToken: #{tracker_token}" "https://www.pivotaltracker.com/services/v5/projects/#{project}/stories"`)
    ids = stories.map do |story|
      story["id"]
    end
    url_body = URI.encode_www_form("ids" => ids.join(','), "fields" => "name,description,tasks,comments(text,person(name,username))")
    stories = JSON.load(`curl -X GET -H "X-TrackerToken: #{tracker_token}" "https://www.pivotaltracker.com/services/v5/projects/#{project}/stories/bulk?#{url_body}"`)
    stories.map do |story|
      @stories[story['id'].to_i] = story
      "#{story['id']}.story"
    end
  end

  def file?(path)
    !(/\d+\.story$/ =~ path).nil?
  end

  def directory?(path)
    !(/\d+\.project$/ =~ path).nil?
  end

  def read_file(path)
    id = path_id(path)
    if @stories[id].nil?
    url_body = URI.encode_www_form("fields" => "name,description,tasks,comments(text,person(name,username))")
      command = "curl -X GET -H \"X-TrackerToken: #{tracker_token}\" \"https://www.pivotaltracker.com/services/v5/projects/#{project}/stories/#{id}?#{url_body}\""
      @stories[id] = JSON.load(`#{command}`)
    end
    YAML.dump(@stories[id])
  end

  def can_write?(path)
    file?(path)
  end

  def write_to(path, body)
    id = path_id(path)

    params = {}
    old_story = @stories[id]

    new_story = YAML.load body

    HashDiff.diff(new_story, old_story) do |object_path, new, old|
      next if new == old || !new
      puts object_path
      puts "new #{new}"
      puts "old #{old}"
      if  /description/.match object_path
        params["description"] = new
      end

      if  /name/.match object_path
        params["name"] = new
      end
    end

    url_body = URI.encode_www_form(params)
    command ="curl -X PUT -H \"X-TrackerToken: #{tracker_token}\" \"https://www.pivotaltracker.com/services/v5/projects/#{project}/stories/#{id}?#{url_body}\""
    puts command

    `#{command}`

    @stories[id] = nil
  end

end

# Usage: TRACKER_TOKEN=<your_token> PROJECT_ID=<project id> ruby filesystem.rb <mountpoint> [mount_options]
FuseFS.main() { |options| Stories.new }
