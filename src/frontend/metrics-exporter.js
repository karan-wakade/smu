/**
 * Simple metrics exporter for Prometheus monitoring of the frontend
 * This file is served by Nginx at /metrics endpoint
 */

(function () {
  // Basic metrics for frontend monitoring
  const metrics = {
    // Counter metrics
    http_requests_total: {},
    page_views_total: {},
    js_errors_total: 0,

    // Gauge metrics
    active_users: 0,

    // Histogram metrics
    page_load_time_seconds: {
      sum: 0,
      count: 0,
      buckets: {
        0.1: 0,
        0.5: 0,
        "1.0": 0,
        "2.0": 0,
        "5.0": 0,
        "+Inf": 0,
      },
    },

    // Initialize with some sample data (in production, these would be real values)
    init: function () {
      this.http_requests_total = {
        200: 42,
        404: 2,
        500: 0,
      };
      this.page_views_total = {
        home: 24,
        about: 8,
        dashboard: 10,
      };
      this.js_errors_total = 0;
      this.active_users = 3;

      // Simulate some page load times
      this.recordPageLoadTime(0.8);
      this.recordPageLoadTime(1.2);
      this.recordPageLoadTime(0.3);
    },

    // Record a page load time and update histogram buckets
    recordPageLoadTime: function (seconds) {
      this.page_load_time_seconds.sum += seconds;
      this.page_load_time_seconds.count += 1;

      // Update appropriate histogram buckets
      for (const threshold in this.page_load_time_seconds.buckets) {
        if (seconds <= parseFloat(threshold) || threshold === "+Inf") {
          this.page_load_time_seconds.buckets[threshold] += 1;
        }
      }
    },

    // Format metrics for Prometheus
    formatMetrics: function () {
      let output = "";

      // Counter: HTTP requests by status code
      output +=
        "# HELP http_requests_total Total number of HTTP requests by status code\n";
      output += "# TYPE http_requests_total counter\n";
      for (const status in this.http_requests_total) {
        output += `http_requests_total{status="${status}"} ${this.http_requests_total[status]}\n`;
      }

      // Counter: Page views by route
      output += "# HELP page_views_total Total number of page views by route\n";
      output += "# TYPE page_views_total counter\n";
      for (const route in this.page_views_total) {
        output += `page_views_total{route="${route}"} ${this.page_views_total[route]}\n`;
      }

      // Counter: JavaScript errors
      output += "# HELP js_errors_total Total number of JavaScript errors\n";
      output += "# TYPE js_errors_total counter\n";
      output += `js_errors_total ${this.js_errors_total}\n`;

      // Gauge: Active users
      output += "# HELP active_users Current number of active users\n";
      output += "# TYPE active_users gauge\n";
      output += `active_users ${this.active_users}\n`;

      // Histogram: Page load times
      output += "# HELP page_load_time_seconds Page load time in seconds\n";
      output += "# TYPE page_load_time_seconds histogram\n";

      for (const bucket in this.page_load_time_seconds.buckets) {
        const le = bucket === "+Inf" ? "+Inf" : bucket;
        output += `page_load_time_seconds_bucket{le="${le}"} ${this.page_load_time_seconds.buckets[bucket]}\n`;
      }

      output += `page_load_time_seconds_sum ${this.page_load_time_seconds.sum}\n`;
      output += `page_load_time_seconds_count ${this.page_load_time_seconds.count}\n`;

      return output;
    },
  };

  // Initialize metrics with sample data
  metrics.init();

  // In a real app, you'd expose a way to update these metrics
  // For now, just expose the Prometheus formatted metrics
  if (typeof module !== "undefined" && module.exports) {
    module.exports = metrics;
  } else if (typeof window !== "undefined") {
    window.PrometheusMetrics = metrics;
  }

  // For Nginx Lua integration or direct serving
  return metrics.formatMetrics();
})();
