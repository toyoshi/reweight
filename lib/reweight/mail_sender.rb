# frozen_string_literal: true

require "net/http"
require "json"
require "uri"
require "date"

module Reweight
  class MailSender
    API_BASE = "https://connect.mailerlite.com"
    OUTPUT_DIR = File.expand_path("../../output", __dir__)

    def configured?
      !Config.mailerlite_api_token.nil? && !Config.mailerlite_group_id.nil?
    end

    def send_today(date: Date.today)
      path = File.join(OUTPUT_DIR, "#{date.strftime('%Y-%m-%d')}.md")
      unless File.exist?(path)
        warn "Output file not found: #{path}"
        return
      end

      markdown = File.read(path)
      html = markdown_to_html(markdown)
      subject = "#{date.month}月#{date.day}日のおだやかニュース"

      campaign_id = create_campaign(subject)
      return unless campaign_id

      return unless set_content(campaign_id, subject, html)

      schedule(campaign_id)
    end

    private

    def api_token
      Config.mailerlite_api_token
    end

    def group_id
      Config.mailerlite_group_id
    end

    def create_campaign(subject)
      body = {
        name: subject,
        type: "regular",
        emails: [{
          subject: subject,
          from_name: "Reweight",
          from: "r@toyoshi.jp"
        }],
        groups: [group_id]
      }

      res = api_post("/api/campaigns", body)
      unless res
        warn "Failed to create campaign"
        return nil
      end

      res["data"]["id"]
    end

    def set_content(campaign_id, subject, html)
      body = {
        name: subject,
        emails: [{
          subject: subject,
          from_name: "Reweight",
          from: "r@toyoshi.jp",
          content: html
        }]
      }
      res = api_put("/api/campaigns/#{campaign_id}", body)
      unless res
        warn "Failed to set campaign content"
        return false
      end
      true
    end

    def schedule(campaign_id)
      body = { delivery: "instant" }
      res = api_post("/api/campaigns/#{campaign_id}/schedule", body)
      unless res
        warn "Failed to schedule campaign"
        return false
      end

      puts "Campaign sent successfully!"
      true
    end

    def api_post(path, body)
      api_request(:post, path, body)
    end

    def api_put(path, body)
      api_request(:put, path, body)
    end

    def api_request(method, path, body)
      uri = URI("#{API_BASE}#{path}")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      req = case method
            when :post then Net::HTTP::Post.new(uri.path)
            when :put  then Net::HTTP::Put.new(uri.path)
            end

      req["Content-Type"] = "application/json"
      req["Authorization"] = "Bearer #{api_token}"
      req.body = JSON.generate(body)

      response = http.request(req)

      unless response.is_a?(Net::HTTPSuccess)
        warn "MailerLite API error: #{response.code} #{response.body}"
        return nil
      end

      JSON.parse(response.body)
    end

    def markdown_to_html(markdown)
      lines = markdown.lines.map(&:chomp)
      html_parts = []
      i = 0

      while i < lines.size
        line = lines[i]

        case line
        when /\A# (.+)/
          html_parts << %(<h1 style="font-size:24px;color:#333;margin:0 0 8px;text-align:center;">#{escape_html(Regexp.last_match(1))}</h1>)
        when /\A## (.+)/
          html_parts << %(<h2 style="font-size:18px;color:#222;margin:0 0 6px;">#{escape_html(Regexp.last_match(1))}</h2>)
        when /\A---\s*\z/
          html_parts << %(<hr style="border:none;border-top:1px solid #e0e0e0;margin:24px 0;">)
        when /\A<!-- center -->(.+)/
          html_parts << %(<p style="font-size:15px;line-height:1.7;color:#999;margin:0 0 20px;text-align:center;">#{escape_html(Regexp.last_match(1))}</p>)
        when /\A\s*\z/
          # skip blank lines
        else
          html_parts << %(<p style="font-size:15px;line-height:1.7;color:#444;margin:0 0 12px;">#{convert_inline(line)}</p>)
        end

        i += 1
      end

      wrap_html(html_parts.join("\n"))
    end

    def convert_inline(text)
      escaped = escape_html(text)
      # Convert [text](url) to <a>
      escaped.gsub(/\[([^\]]+)\]\(([^)]+)\)/) do
        %(<a href="#{Regexp.last_match(2)}" style="color:#1a73e8;text-decoration:underline;">#{Regexp.last_match(1)}</a>)
      end.then do |s|
        # Convert *text* to <em>
        s.gsub(/\*([^*]+)\*/, '<em>\1</em>')
      end
    end

    def escape_html(text)
      text.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;").gsub('"', "&quot;")
    end

    def wrap_html(body)
      <<~HTML
        <!DOCTYPE html>
        <html>
        <head><meta charset="utf-8"></head>
        <body style="margin:0;padding:0;background-color:#f5f5f5;font-family:sans-serif;">
          <table width="100%" cellpadding="0" cellspacing="0" style="background-color:#f5f5f5;">
            <tr>
              <td align="center" style="padding:24px 16px;">
                <table width="600" cellpadding="0" cellspacing="0" style="background-color:#ffffff;border-radius:8px;overflow:hidden;max-width:600px;width:100%;">
                  <tr>
                    <td style="padding:32px 24px;">
                      #{body}
                    </td>
                  </tr>
                </table>
                <p style="font-size:12px;color:#999;margin-top:16px;text-align:center;">
                  <a href="{$unsubscribe}" style="color:#999;">配信解除</a>
                </p>
              </td>
            </tr>
          </table>
        </body>
        </html>
      HTML
    end
  end
end
