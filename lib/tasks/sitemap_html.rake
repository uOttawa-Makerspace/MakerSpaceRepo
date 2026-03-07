# lib/tasks/sitemap_html.rake

namespace :sitemap do
  desc "Generate interactive HTML sitemap visualization"
  task html: :environment do
    require 'nokogiri'
    require 'zlib'
    require 'json'

    sitemap_path = Rails.root.join('public', 'sitemap.xml.gz')
    output_path = Rails.root.join('public', 'sitemap_visual.html')

    unless File.exist?(sitemap_path)
      puts "❌ Sitemap not found. Run 'rake sitemap:refresh' first."
      exit 1
    end

    # Parse the sitemap
    xml_content = Zlib::GzipReader.open(sitemap_path) { |gz| gz.read }
    doc = Nokogiri::XML(xml_content)

    # Build hierarchical structure
    pages = []
    root = { name: "makerepo.com", path: "/", children: [], priority: "1.0", changefreq: "daily" }

    doc.xpath('//xmlns:url').each do |url_node|
      loc = url_node.at_xpath('xmlns:loc')&.text
      priority = url_node.at_xpath('xmlns:priority')&.text || "0.5"
      changefreq = url_node.at_xpath('xmlns:changefreq')&.text || "weekly"
      lastmod = url_node.at_xpath('xmlns:lastmod')&.text

      path = URI.parse(loc).path
      segments = path.split('/').reject(&:empty?)

      pages << {
        path: path.empty? ? "/" : path,
        priority: priority,
        changefreq: changefreq,
        lastmod: lastmod
      }

      # Skip root, it's already added
      next if segments.empty?

      current = root
      segments.each_with_index do |segment, idx|
        existing = current[:children].find { |c| c[:name] == segment }
        if existing
          current = existing
        else
          is_leaf = idx == segments.length - 1
          new_node = {
            name: segment,
            path: "/" + segments[0..idx].join('/'),
            children: [],
            priority: is_leaf ? priority : nil,
            changefreq: is_leaf ? changefreq : nil
          }
          current[:children] << new_node
          current = new_node
        end
      end
    end

    # Sort children alphabetically
    sort_children(root)

    # Generate HTML
    html_content = generate_html(root, pages)
    File.write(output_path, html_content)

    puts ""
    puts "✅ Interactive sitemap visualization generated!"
    puts "📍 Location: #{output_path}"
    puts "🌐 View at: https://makerepo.com/sitemap_visual.html"
    puts ""
    puts "📊 Statistics:"
    puts "   Total pages: #{pages.count}"
    puts "   High priority (≥0.7): #{pages.count { |p| p[:priority].to_f >= 0.7 }}"
    puts "   Medium priority (0.4-0.6): #{pages.count { |p| p[:priority].to_f.between?(0.4, 0.6) }}"
    puts "   Low priority (≤0.3): #{pages.count { |p| p[:priority].to_f <= 0.3 }}"
    puts ""
  end

  def sort_children(node)
    return unless node[:children]
    node[:children].sort_by! { |c| c[:name] }
    node[:children].each { |child| sort_children(child) }
  end

  def generate_html(tree_data, pages_list)
    <<~HTML
      <!DOCTYPE html>
      <html lang="en">
      <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Sitemap Visualization - MakeRepo</title>
        <script src="https://d3js.org/d3.v7.min.js"></script>
        <style>
          * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
          }

          body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif;
            background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
            min-height: 100vh;
            color: #fff;
          }

          .container {
            max-width: 1400px;
            margin: 0 auto;
            padding: 20px;
          }

          header {
            text-align: center;
            padding: 30px 0;
            border-bottom: 1px solid rgba(255,255,255,0.1);
            margin-bottom: 30px;
          }

          h1 {
            font-size: 2.5rem;
            margin-bottom: 10px;
            background: linear-gradient(90deg, #00d9ff, #00ff88);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
            background-clip: text;
          }

          .subtitle {
            color: #888;
            font-size: 1.1rem;
          }

          .stats-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
          }

          .stat-card {
            background: rgba(255,255,255,0.05);
            border-radius: 12px;
            padding: 20px;
            text-align: center;
            border: 1px solid rgba(255,255,255,0.1);
          }

          .stat-number {
            font-size: 2.5rem;
            font-weight: bold;
            margin-bottom: 5px;
          }

          .stat-label {
            color: #888;
            font-size: 0.9rem;
          }

          .stat-card.total .stat-number { color: #00d9ff; }
          .stat-card.high .stat-number { color: #00ff88; }
          .stat-card.medium .stat-number { color: #ffcc00; }
          .stat-card.low .stat-number { color: #ff6b6b; }

          .tabs {
            display: flex;
            gap: 10px;
            margin-bottom: 20px;
          }

          .tab {
            padding: 12px 24px;
            background: rgba(255,255,255,0.05);
            border: 1px solid rgba(255,255,255,0.1);
            border-radius: 8px;
            cursor: pointer;
            transition: all 0.3s;
            color: #fff;
          }

          .tab:hover, .tab.active {
            background: rgba(0,217,255,0.2);
            border-color: #00d9ff;
          }

          .view-container {
            background: rgba(255,255,255,0.03);
            border-radius: 16px;
            border: 1px solid rgba(255,255,255,0.1);
            overflow: hidden;
          }

          .tree-view {
            padding: 30px;
            overflow-x: auto;
          }

          .tree-view svg {
            display: block;
            margin: 0 auto;
          }

          .list-view {
            display: none;
            padding: 20px;
          }

          .list-view.active, .tree-view.active {
            display: block;
          }

          .page-table {
            width: 100%;
            border-collapse: collapse;
          }

          .page-table th,
          .page-table td {
            padding: 12px 16px;
            text-align: left;
            border-bottom: 1px solid rgba(255,255,255,0.05);
          }

          .page-table th {
            background: rgba(255,255,255,0.05);
            font-weight: 600;
            color: #00d9ff;
          }

          .page-table tr:hover {
            background: rgba(255,255,255,0.02);
          }

          .page-table a {
            color: #00ff88;
            text-decoration: none;
          }

          .page-table a:hover {
            text-decoration: underline;
          }

          .priority-badge {
            padding: 4px 12px;
            border-radius: 20px;
            font-size: 0.85rem;
            font-weight: 500;
          }

          .priority-high { background: rgba(0,255,136,0.2); color: #00ff88; }
          .priority-medium { background: rgba(255,204,0,0.2); color: #ffcc00; }
          .priority-low { background: rgba(255,107,107,0.2); color: #ff6b6b; }

          .freq-badge {
            padding: 4px 10px;
            border-radius: 6px;
            font-size: 0.8rem;
            background: rgba(255,255,255,0.1);
            color: #ccc;
          }

          /* D3 Tree Styles */
          .node circle {
            stroke-width: 3px;
            cursor: pointer;
            transition: all 0.3s;
          }

          .node circle:hover {
            filter: brightness(1.3);
          }

          .node text {
            font-size: 12px;
            fill: #fff;
          }

          .link {
            fill: none;
            stroke: rgba(255,255,255,0.2);
            stroke-width: 2px;
          }

          .tooltip {
            position: absolute;
            background: rgba(0,0,0,0.9);
            border: 1px solid #00d9ff;
            border-radius: 8px;
            padding: 12px 16px;
            font-size: 13px;
            pointer-events: none;
            z-index: 1000;
            max-width: 300px;
          }

          .tooltip-path {
            color: #00ff88;
            font-weight: bold;
            margin-bottom: 8px;
            word-break: break-all;
          }

          .tooltip-info {
            color: #ccc;
          }

          .legend {
            display: flex;
            justify-content: center;
            gap: 30px;
            padding: 20px;
            flex-wrap: wrap;
          }

          .legend-item {
            display: flex;
            align-items: center;
            gap: 8px;
          }

          .legend-dot {
            width: 16px;
            height: 16px;
            border-radius: 50%;
          }

          .excluded-section {
            margin-top: 40px;
            padding: 20px;
            background: rgba(255,107,107,0.1);
            border-radius: 12px;
            border: 1px solid rgba(255,107,107,0.3);
          }

          .excluded-section h3 {
            color: #ff6b6b;
            margin-bottom: 15px;
          }

          .excluded-list {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(200px, 1fr));
            gap: 10px;
          }

          .excluded-item {
            display: flex;
            align-items: center;
            gap: 8px;
            color: #888;
          }

          footer {
            text-align: center;
            padding: 30px;
            color: #666;
            font-size: 0.9rem;
          }
        </style>
      </head>
      <body>
        <div class="container">
          <header>
            <h1>🗺️ MakeRepo Sitemap</h1>
            <p class="subtitle">Interactive visualization of site structure</p>
          </header>

          <div class="stats-grid">
            <div class="stat-card total">
              <div class="stat-number" id="total-pages">#{pages_list.count}</div>
              <div class="stat-label">Total Pages</div>
            </div>
            <div class="stat-card high">
              <div class="stat-number">#{pages_list.count { |p| p[:priority].to_f >= 0.7 }}</div>
              <div class="stat-label">High Priority (≥0.7)</div>
            </div>
            <div class="stat-card medium">
              <div class="stat-number">#{pages_list.count { |p| p[:priority].to_f.between?(0.4, 0.69) }}</div>
              <div class="stat-label">Medium Priority</div>
            </div>
            <div class="stat-card low">
              <div class="stat-number">#{pages_list.count { |p| p[:priority].to_f <= 0.3 }}</div>
              <div class="stat-label">Low Priority (≤0.3)</div>
            </div>
          </div>

          <div class="tabs">
            <button class="tab active" onclick="showView('tree')">🌳 Tree View</button>
            <button class="tab" onclick="showView('list')">📋 List View</button>
          </div>

          <div class="view-container">
            <div class="tree-view active" id="tree-view">
              <div id="tree-chart"></div>
              <div class="legend">
                <div class="legend-item">
                  <div class="legend-dot" style="background: #00ff88;"></div>
                  <span>High Priority (≥0.7)</span>
                </div>
                <div class="legend-item">
                  <div class="legend-dot" style="background: #ffcc00;"></div>
                  <span>Medium Priority (0.4-0.6)</span>
                </div>
                <div class="legend-item">
                  <div class="legend-dot" style="background: #ff6b6b;"></div>
                  <span>Low Priority (≤0.3)</span>
                </div>
                <div class="legend-item">
                  <div class="legend-dot" style="background: #00d9ff;"></div>
                  <span>Category Node</span>
                </div>
              </div>
            </div>

            <div class="list-view" id="list-view">
              <table class="page-table">
                <thead>
                  <tr>
                    <th>Path</th>
                    <th>Priority</th>
                    <th>Change Frequency</th>
                  </tr>
                </thead>
                <tbody>
                  #{generate_table_rows(pages_list)}
                </tbody>
              </table>
            </div>
          </div>

          <div class="excluded-section">
            <h3>❌ Excluded from Sitemap</h3>
            <div class="excluded-list">
              <div class="excluded-item">🔒 /admin/* (Admin area)</div>
              <div class="excluded-item">🔍 /search (robots.txt blocked)</div>
              <div class="excluded-item">🖼️ /explore (Heavy images)</div>
              <div class="excluded-item">🔑 /login (Auth pages)</div>
              <div class="excluded-item">📝 /signup (Auth pages)</div>
              <div class="excluded-item">🔐 /password/* (Auth pages)</div>
              <div class="excluded-item">👤 /session/* (Auth pages)</div>
            </div>
          </div>

          <footer>
            Generated on #{Time.current.strftime('%B %d, %Y at %H:%M %Z')}<br>
            Using sitemap_generator gem
          </footer>
        </div>

        <div class="tooltip" id="tooltip" style="display: none;"></div>

        <script>
          const treeData = #{tree_data.to_json};

          function showView(view) {
            document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
            document.querySelectorAll('.tree-view, .list-view').forEach(v => v.classList.remove('active'));
            
            event.target.classList.add('active');
            document.getElementById(view + '-view').classList.add('active');
          }

          function getPriorityColor(priority) {
            const p = parseFloat(priority) || 0.5;
            if (p >= 0.7) return '#00ff88';
            if (p >= 0.4) return '#ffcc00';
            return '#ff6b6b';
          }

          // D3.js Tree Visualization
          const width = 1200;
          const height = 600;
          const margin = { top: 20, right: 120, bottom: 20, left: 120 };

          const svg = d3.select("#tree-chart")
            .append("svg")
            .attr("width", width)
            .attr("height", height)
            .attr("viewBox", [0, 0, width, height]);

          const g = svg.append("g")
            .attr("transform", `translate(${margin.left},${margin.top})`);

          const treeLayout = d3.tree()
            .size([height - margin.top - margin.bottom, width - margin.left - margin.right]);

          const root = d3.hierarchy(treeData);
          treeLayout(root);

          // Links
          g.selectAll(".link")
            .data(root.links())
            .enter()
            .append("path")
            .attr("class", "link")
            .attr("d", d3.linkHorizontal()
              .x(d => d.y)
              .y(d => d.x));

          // Nodes
          const node = g.selectAll(".node")
            .data(root.descendants())
            .enter()
            .append("g")
            .attr("class", "node")
            .attr("transform", d => `translate(${d.y},${d.x})`);

          node.append("circle")
            .attr("r", d => d.children ? 8 : 10)
            .attr("fill", d => {
              if (d.data.priority) return getPriorityColor(d.data.priority);
              return '#00d9ff';
            })
            .attr("stroke", d => {
              if (d.data.priority) return getPriorityColor(d.data.priority);
              return '#00d9ff';
            })
            .on("mouseover", function(event, d) {
              const tooltip = document.getElementById('tooltip');
              tooltip.innerHTML = `
                <div class="tooltip-path">${d.data.path || '/'}</div>
                <div class="tooltip-info">
                  ${d.data.priority ? `Priority: ${d.data.priority}<br>` : ''}
                  ${d.data.changefreq ? `Updates: ${d.data.changefreq}` : ''}
                  ${!d.data.priority && !d.data.changefreq ? 'Category node' : ''}
                </div>
              `;
              tooltip.style.display = 'block';
              tooltip.style.left = (event.pageX + 10) + 'px';
              tooltip.style.top = (event.pageY - 10) + 'px';
            })
            .on("mouseout", function() {
              document.getElementById('tooltip').style.display = 'none';
            })
            .on("click", function(event, d) {
              if (d.data.path) {
                window.open('https://makerepo.com' + d.data.path, '_blank');
              }
            });

          node.append("text")
            .attr("dy", "0.35em")
            .attr("x", d => d.children ? -15 : 15)
            .attr("text-anchor", d => d.children ? "end" : "start")
            .text(d => d.data.name)
            .style("font-size", "11px");
        </script>
      </body>
      </html>
    HTML
  end

  def generate_table_rows(pages)
    pages.sort_by { |p| -p[:priority].to_f }.map do |page|
      priority_class = case page[:priority].to_f
                       when 0.7..1.0 then "priority-high"
                       when 0.4...0.7 then "priority-medium"
                       else "priority-low"
                       end

      <<~ROW
        <tr>
          <td><a href="https://makerepo.com#{page[:path]}" target="_blank">#{page[:path]}</a></td>
          <td><span class="priority-badge #{priority_class}">#{page[:priority]}</span></td>
          <td><span class="freq-badge">#{page[:changefreq]}</span></td>
        </tr>
      ROW
    end.join
  end
end