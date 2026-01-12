module Jekyll
  class SrcPage < Page
    def initialize(site, base, relative_dir, name)
      @site = site
      @base = base
      @dir  = relative_dir
      @name = name

      self.process(name)
      
      # Read the YAML data from the source file
      # We construct the source directory path manually
      src_dir = File.join(base, 'src', 'pages', relative_dir)
      self.read_yaml(src_dir, name)
      
      self.data['layout'] ||= 'page'
    end
  end

  class SrcPagesGenerator < Generator
    safe true
    priority :low

    def generate(site)
      src_root = File.join(site.source, 'src', 'pages')
      return unless File.directory?(src_root)

      # Glob all markdown and html files in src/pages
      Dir.glob(File.join(src_root, '**', '*.{md,html}')).each do |file|
        # Get relative path from src/pages
        relative_path = File.dirname(file).sub(src_root, '').sub(%r{^/}, '')
        name = File.basename(file)

        # Create the page
        site.pages << SrcPage.new(site, site.source, relative_path, name)
      end
    end
  end
end
