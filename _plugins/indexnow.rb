# IndexNow Integration for Jekyll (SEO Playbook 2026)
# Automatically submits URLs to IndexNow-compatible search engines on build
#
# Configuration in _config.yml:
#   indexnow:
#     enabled: true
#     key: "your-indexnow-key"
#
# The key file should be placed at /indexnow-key.txt

require 'net/http'
require 'uri'
require 'json'

module Jekyll
  class IndexNowGenerator < Generator
    safe true
    priority :lowest

    INDEXNOW_ENDPOINTS = [
      'https://api.indexnow.org/indexnow',
      'https://www.bing.com/indexnow'
    ].freeze

    def generate(site)
      return unless site.config.dig('indexnow', 'enabled')
      
      key = site.config.dig('indexnow', 'key')
      return unless key

      host = URI.parse(site.config['url']).host
      key_location = "#{site.config['url']}/#{key}.txt"

      urls = collect_urls(site)
      
      # Store URLs for later submission (post-build hook or manual trigger)
      site.data['indexnow_urls'] = urls
      site.data['indexnow_key'] = key
      site.data['indexnow_host'] = host

      # Generate the key file
      generate_key_file(site, key)
      
      Jekyll.logger.info "IndexNow:", "Prepared #{urls.length} URLs for submission"
    end

    private

    def collect_urls(site)
      urls = []

      # Collect post URLs
      site.posts.docs.each do |post|
        urls << site.config['url'] + post.url
      end

      # Collect page URLs (excluding sitemaps, feeds, etc.)
      site.pages.each do |page|
        next if page.url.include?('sitemap')
        next if page.url.include?('feed')
        next if page.url.include?('404')
        next if page.data['sitemap'] == false
        
        urls << site.config['url'] + page.url
      end

      # Collect topic hub URLs
      if site.collections['topics']
        site.collections['topics'].docs.each do |topic|
          urls << site.config['url'] + topic.url
        end
      end

      urls.uniq
    end

    def generate_key_file(site, key)
      # Create the key verification file
      key_page = PageWithoutAFile.new(site, site.source, '', "#{key}.txt")
      key_page.content = key
      key_page.data['layout'] = nil
      site.pages << key_page
    end
  end
end

# Rake task for manual IndexNow submission
# Run: bundle exec rake indexnow:submit
namespace :indexnow do
  desc "Submit URLs to IndexNow"
  task :submit do
    require 'yaml'
    require 'net/http'
    require 'json'

    config = YAML.load_file('_config.yml')
    key = config.dig('indexnow', 'key')
    
    unless key
      puts "IndexNow key not configured in _config.yml"
      exit 1
    end

    host = URI.parse(config['url']).host
    
    # Read URLs from sitemap or generate
    urls = []
    Dir.glob('_site/**/*.html').each do |file|
      path = file.sub('_site', '').sub('/index.html', '/').sub('.html', '.html')
      urls << config['url'] + path
    end

    payload = {
      host: host,
      key: key,
      keyLocation: "#{config['url']}/#{key}.txt",
      urlList: urls.take(10000) # IndexNow limit
    }

    uri = URI('https://api.indexnow.org/indexnow')
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(uri.path)
    request['Content-Type'] = 'application/json'
    request.body = payload.to_json

    response = http.request(request)
    
    puts "IndexNow Response: #{response.code}"
    puts "Submitted #{urls.length} URLs"
  end
end
