# Rakefile for SEO tasks
require 'net/http'
require 'uri'
require 'json'
require 'yaml'

namespace :indexnow do
  desc "Submit URLs to IndexNow after build"
  task :submit do
    config = YAML.load_file('_config.yml')
    key = config.dig('indexnow', 'key')
    
    unless key
      puts "IndexNow key not configured in _config.yml"
      exit 1
    end

    host = URI.parse(config['url']).host
    
    urls = []
    Dir.glob('_site/**/*.html').each do |file|
      next if file.include?('404') || file.include?('sitemap')
      path = file.sub('_site', '').sub('/index.html', '/').sub('.html', '.html')
      urls << config['url'] + path
    end

    payload = {
      host: host,
      key: key,
      keyLocation: "#{config['url']}/#{key}.txt",
      urlList: urls.take(10000)
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

namespace :seo do
  desc "Validate SEO requirements locally"
  task :validate do
    errors = []
    warnings = []

    Dir.glob('_site/**/*.html').each do |file|
      content = File.read(file)
      
      # Check for title
      unless content.include?('<title>')
        errors << "Missing <title> in #{file}"
      end
      
      # Check for meta description (warning only)
      unless content.include?('name="description"') || file.include?('404') || file.include?('sitemap')
        warnings << "Missing meta description in #{file}"
      end
      
      # Check for multiple H1 tags
      h1_count = content.scan(/<h1/i).length
      if h1_count > 1
        errors << "Multiple H1 tags (#{h1_count}) in #{file}"
      end
      
      # Check for canonical URL
      unless content.include?('rel="canonical"') || file.include?('404') || file.include?('sitemap')
        warnings << "Missing canonical URL in #{file}"
      end
    end

    if errors.any?
      puts "\n❌ ERRORS:"
      errors.each { |e| puts "  - #{e}" }
    end

    if warnings.any?
      puts "\n⚠️  WARNINGS:"
      warnings.each { |w| puts "  - #{w}" }
    end

    if errors.empty? && warnings.empty?
      puts "✅ All SEO checks passed!"
    end

    exit 1 if errors.any?
  end
end
