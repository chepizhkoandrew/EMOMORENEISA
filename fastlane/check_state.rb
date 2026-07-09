require "net/http"
require "uri"
require "json"
require "openssl"
require "jwt"

KEY_PATH  = "/Users/andriichepizhko/Downloads/IOSSPANISHGAME/appstore/keys/AuthKey_V86ZAHA4K5.p8"
KEY_ID    = "V86ZAHA4K5"
ISSUER_ID = "3ef7a3d5-c267-47e3-e053-5b8c7c11a4d1"
APPLE_ID  = "6782026883"

private_key = OpenSSL::PKey::EC.new(File.read(KEY_PATH))
now   = Time.now.to_i
token = JWT.encode(
  { iss: ISSUER_ID, iat: now, exp: now + 1200, aud: "appstoreconnect-v1" },
  private_key, "ES256",
  { kid: KEY_ID }
)

base    = "https://api.appstoreconnect.apple.com/v1"
headers = { "Authorization" => "Bearer #{token}", "Content-Type" => "application/json" }

asc_get = lambda do |path|
  uri  = URI("#{base}#{path}")
  req  = Net::HTTP::Get.new(uri)
  headers.each { |k, v| req[k] = v }
  resp = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
  JSON.parse(resp.body)
end

puts "\n=== ALL iOS VERSIONS ==="
versions = asc_get.call("/apps/#{APPLE_ID}/appStoreVersions?filter[platform]=IOS&limit=10")
(versions["data"] || []).each do |v|
  puts "  v#{v.dig('attributes','versionString')} | state=#{v.dig('attributes','appStoreState')} | id=#{v['id']}"
end

puts "\n=== IAPs ==="
iaps = asc_get.call("/apps/#{APPLE_ID}/inAppPurchasesV2?limit=50")
(iaps["data"] || []).each do |iap|
  pid   = iap.dig("attributes", "productId")
  state = iap.dig("attributes", "state")
  puts "  #{pid.to_s.ljust(22)} state=#{state}  id=#{iap['id']}"
end

puts "\n=== REVIEW SUBMISSIONS ==="
subs = asc_get.call("/apps/#{APPLE_ID}/reviewSubmissions?limit=10")
(subs["data"] || []).each do |s|
  puts "  id=#{s['id']} state=#{s.dig('attributes','state')} platform=#{s.dig('attributes','platform')}"
end
