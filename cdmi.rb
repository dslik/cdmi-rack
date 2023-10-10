require "rack"
require "json"

class CDMI
  def call(env)
    req = Rack::Request.new(env)
    response = Rack::Response.new


    response.write JSON.pretty_generate(env)
    response.status = 200
    response.finish
  end
end
