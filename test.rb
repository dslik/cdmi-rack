# Simple ruby rack test runner
require "json"
require_relative "cdmi"

# ===============================================
# Utility routine to convert HTTP response codes
def lookup_response_code(code)
	if(code == 200)
		return("OK")
	end

	if(code == 404)
		return("NOT FOUND")
	end
end

# ===============================================
# Set up the rack env

env = Hash.new()
env["rack.version"] = Array.new()
env["rack.version"] << 1
env["rack.version"] << 6
env["rack.multithread"] = "false"
env["rack.multiprocess"] = "false"
env["rack.run_once"] = "true"
env["rack.url_scheme"] = "http"

env["SCRIPT_NAME"] = ""
env["SERVER_SOFTWARE"] = "CDMI Test Runner"
env["GATEWAY_INTERFACE"] = "CGI_1.2"
env["REMOTE_ADDR"] = "127.0.0.1"

env["rack.after_reply"] = Array.new()

# ===============================================
# Extract the HTTP Request
print "Reading test file \"#{ARGV[0]}\"\n";
file = File.open(ARGV[0], "r");
http_request = file.gets

# Extract the request method
env["REQUEST_METHOD"] = http_request.slice(0, http_request.index(" "))

# Extract the request URI
http_request = http_request.slice(http_request.index(" ") + 1, http_request.length)
env["REQUEST_URI"] = http_request.slice(0, http_request.index(" "))

# Extract the request path
if(env["REQUEST_URI"].index("?"))
	env["REQUEST_PATH"] = env["REQUEST_URI"].slice(0, env["REQUEST_URI"].index("?"))
else
	env["REQUEST_PATH"] = env["REQUEST_URI"]
end

# Extract the query parameters
if(env["REQUEST_PATH"].length != env["REQUEST_URI"].length)
	env["QUERY_STRING"] = env["REQUEST_URI"].slice(env["REQUEST_URI"].index("?") + 1, env["REQUEST_URI"].length)
else
	env["QUERY_STRING"] = ""
end

# Extract the request protocol
http_request = http_request.slice(http_request.index(" ") + 1, http_request.length)
http_request = http_request.slice(0, http_request.length - 1)
env["SERVER_PROTOCOL"] = http_request
env["HTTP_VERSION"] = http_request

# ===============================================
# Extract the HTTP Headers
http_header = file.gets

while(http_header != nil && http_header.length > 1)
	env["HTTP_" + http_header.slice(0, http_header.index(":")).upcase] = http_header.slice(http_header.index(":") + 2, http_header.length - http_header.index(":") - 3)
	http_header = file.gets
end

if(env["HTTP_HOST"])
	if(env["HTTP_HOST"].index(":"))
		env["SERVER_NAME"] = env["HTTP_HOST"].split(0, env["HTTP_HOST"].index(":"))
		env["SERVER_PORT"] = env["HTTP_HOST"].split(env["HTTP_HOST"].index(":") + 1, env["HTTP_HOST"].length)
	else
		env["SERVER_NAME"] = env["HTTP_HOST"]
	end
end

json_text = file.read

if(json_text.length > 2)
	env["rack.input"] = json_text
end

# ===============================================
# Run the rack handler
cdmi_instance = CDMI.new
response = cdmi_instance.call(env)

# ===============================================
# Print the resulting HTTP response body
print "HTTP " + response[0].to_s + " " + lookup_response_code(response[0]) + "\n"
response[1].each do |header|
	print header[0] + ": " + header[1] + "\n"
end

print "\n"

print JSON.pretty_generate(JSON.parse(response[2][0]))
